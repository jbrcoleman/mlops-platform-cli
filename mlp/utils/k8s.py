"""Kubernetes utilities for ML job submission and management."""

import time
import base64
import tempfile
import tarfile
from pathlib import Path
from typing import Dict, List, Optional
from kubernetes import client, config as k8s_config
from kubernetes.client.rest import ApiException
from mlp.config import Config
from mlp.utils.logger import setup_logger

logger = setup_logger(__name__)


def get_k8s_client(kubernetes_context: Optional[str] = None):
    """Get Kubernetes API client.

    Args:
        kubernetes_context: K8s context to use (defaults to current context)

    Returns:
        Tuple of (BatchV1Api, CoreV1Api)
    """
    try:
        # Load kubeconfig
        k8s_config.load_kube_config(context=kubernetes_context)
        batch_api = client.BatchV1Api()
        core_api = client.CoreV1Api()
        return batch_api, core_api
    except Exception as e:
        logger.error(f"Failed to load Kubernetes config: {e}")
        raise


def create_configmap_from_path(
    name: str,
    namespace: str,
    path: Path,
    core_api: client.CoreV1Api
) -> str:
    """Create a ConfigMap from a directory.

    Args:
        name: ConfigMap name
        namespace: Kubernetes namespace
        path: Path to directory
        core_api: Kubernetes Core API client

    Returns:
        ConfigMap name
    """
    # Directories and patterns to exclude from ConfigMap
    exclude_patterns = [
        'mlruns', 'models', '.git', '__pycache__', '.ipynb_checkpoints',
        'data', 'notebooks', '.dvc', '.pytest_cache', '.venv', 'venv',
        '*.pyc', '*.pyo', '*.pyd', '.DS_Store', '*.egg-info'
    ]

    def should_exclude(file_path: Path) -> bool:
        """Check if file should be excluded from ConfigMap."""
        relative = file_path.relative_to(path)
        parts = relative.parts

        # Check if any part of the path matches exclude patterns
        for pattern in exclude_patterns:
            # Check directory names
            if pattern in parts:
                return True
            # Check file patterns (e.g., *.pyc)
            if '*' in pattern and file_path.name.endswith(pattern[1:]):
                return True
        return False

    # Read all files in directory
    data = {}
    total_size = 0
    for file_path in path.rglob("*"):
        if file_path.is_file() and not should_exclude(file_path):
            relative_path = file_path.relative_to(path)
            # ConfigMap keys must match regex: [-._a-zA-Z0-9]+
            # Replace path separators with double underscores
            key = str(relative_path).replace("\\", "__").replace("/", "__")
            try:
                # Try reading as text
                content = file_path.read_text()
                data[key] = content
                total_size += len(content)
            except UnicodeDecodeError:
                # If binary, base64 encode
                encoded = base64.b64encode(file_path.read_bytes()).decode()
                data[key] = encoded
                total_size += len(encoded)

    logger.info(f"Packaging {len(data)} files ({total_size / 1024:.1f} KB) into ConfigMap")

    # Warn if approaching size limit (3MB for ConfigMaps)
    if total_size > 2_000_000:  # 2MB warning threshold
        logger.warning(
            f"ConfigMap size ({total_size / 1024 / 1024:.1f} MB) is approaching the 3MB limit. "
            "Consider excluding more files or using a different deployment method."
        )

    # Create ConfigMap
    configmap = client.V1ConfigMap(
        metadata=client.V1ObjectMeta(name=name),
        data=data
    )

    try:
        core_api.create_namespaced_config_map(namespace, configmap)
        logger.info(f"Created ConfigMap: {name}")
    except ApiException as e:
        if e.status == 409:  # Already exists
            core_api.replace_namespaced_config_map(name, namespace, configmap)
            logger.info(f"Updated ConfigMap: {name}")
        else:
            raise

    return name


def submit_training_job(
    name: str,
    experiment_path: Path,
    image: str,
    cpu: str,
    memory: str,
    gpu: int,
    env_vars: Dict[str, str],
    config: Config
) -> str:
    """Submit a training job to Kubernetes.

    Args:
        name: Job name
        experiment_path: Path to experiment directory
        image: Docker image
        cpu: CPU request
        memory: Memory request
        gpu: Number of GPUs
        env_vars: Environment variables
        config: MLP configuration

    Returns:
        Job name
    """
    batch_api, core_api = get_k8s_client(config.kubernetes.context)

    # Create unique job name with timestamp
    job_name = f"{name}-{int(time.time())}"

    # Create ConfigMap from experiment code
    configmap_name = f"{job_name}-code"
    create_configmap_from_path(
        configmap_name,
        config.kubernetes.namespace,
        experiment_path,
        core_api
    )

    # Build environment variables
    env = [
        client.V1EnvVar(name=key, value=value)
        for key, value in env_vars.items()
    ]

    # Resource requirements
    resources = client.V1ResourceRequirements(
        requests={
            "cpu": cpu,
            "memory": memory,
        },
        limits={
            "cpu": cpu,
            "memory": memory,
        }
    )

    # Add GPU if requested
    if gpu > 0:
        resources.requests["nvidia.com/gpu"] = str(gpu)
        resources.limits["nvidia.com/gpu"] = str(gpu)

    # Volume to mount code
    volume = client.V1Volume(
        name="code",
        config_map=client.V1ConfigMapVolumeSource(name=configmap_name)
    )

    volume_mount = client.V1VolumeMount(
        name="code",
        mount_path="/workspace"
    )

    # Container spec
    # Note: ConfigMap files are mounted with __ instead of / in filenames
    # ConfigMaps are read-only, so we need to copy to a writable location first
    container = client.V1Container(
        name="trainer",
        image=image,
        command=["/bin/bash", "-c"],
        args=[
            # Copy from read-only ConfigMap mount to writable location
            "mkdir -p /work && "
            "cd /workspace && "
            # Restore directory structure from flattened ConfigMap keys
            "for f in *; do "
            "  if [[ \"$f\" == *__* ]]; then "
            "    target=\"/work/$(echo \"$f\" | sed 's/__/\\//g')\"; "
            "    mkdir -p \"$(dirname \"$target\")\"; "
            "    cp \"$f\" \"$target\"; "
            "  else "
            "    cp \"$f\" \"/work/$f\"; "
            "  fi; "
            "done && "
            "cd /work && "
            "pip install -r requirements.txt && "
            "python train.py"
        ],
        env=env,
        resources=resources,
        volume_mounts=[volume_mount],
        working_dir="/work"
    )

    # Pod template
    template = client.V1PodTemplateSpec(
        metadata=client.V1ObjectMeta(
            labels={"app": "ml-training", "job": job_name}
        ),
        spec=client.V1PodSpec(
            service_account_name="training-sa",  # Enable IRSA for S3 access
            restart_policy="Never",
            containers=[container],
            volumes=[volume]
        )
    )

    # Job spec
    job_spec = client.V1JobSpec(
        template=template,
        backoff_limit=3,
        ttl_seconds_after_finished=86400  # Clean up after 24 hours
    )

    # Create job
    job = client.V1Job(
        api_version="batch/v1",
        kind="Job",
        metadata=client.V1ObjectMeta(name=job_name),
        spec=job_spec
    )

    try:
        batch_api.create_namespaced_job(config.kubernetes.namespace, job)
        logger.info(f"Created job: {job_name}")
        return job_name
    except ApiException as e:
        logger.error(f"Failed to create job: {e}")
        raise


def wait_for_job(job_name: str, namespace: str, timeout: int = 600):
    """Wait for a job to start running.

    Args:
        job_name: Job name
        namespace: Kubernetes namespace
        timeout: Timeout in seconds
    """
    batch_api, core_api = get_k8s_client()

    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            job = batch_api.read_namespaced_job(job_name, namespace)

            # Check if job has started
            if job.status.active and job.status.active > 0:
                logger.info(f"Job {job_name} is running")
                return

            # Check if job failed
            if job.status.failed and job.status.failed > 0:
                logger.error(f"Job {job_name} failed")
                raise RuntimeError(f"Job {job_name} failed")

            time.sleep(2)
        except ApiException as e:
            logger.error(f"Error checking job status: {e}")
            raise

    raise TimeoutError(f"Job {job_name} did not start within {timeout} seconds")


def stream_job_logs(job_name: str, namespace: str):
    """Stream logs from a job.

    Args:
        job_name: Job name
        namespace: Kubernetes namespace
    """
    batch_api, core_api = get_k8s_client()

    # Find pod for job
    pods = core_api.list_namespaced_pod(
        namespace,
        label_selector=f"job-name={job_name}"
    )

    if not pods.items:
        logger.error(f"No pods found for job {job_name}")
        return

    pod_name = pods.items[0].metadata.name

    try:
        # Stream logs
        logs = core_api.read_namespaced_pod_log(
            pod_name,
            namespace,
            follow=True,
            _preload_content=False
        )

        for line in logs.stream():
            print(line.decode('utf-8'), end='')

    except ApiException as e:
        logger.error(f"Error streaming logs: {e}")
        raise


def list_jobs(namespace: str, status_filter: str = "all") -> List[Dict]:
    """List ML training jobs.

    Args:
        namespace: Kubernetes namespace
        status_filter: Filter by status (all, running, completed, failed)

    Returns:
        List of job information dictionaries
    """
    batch_api, _ = get_k8s_client()

    try:
        jobs = batch_api.list_namespaced_job(
            namespace,
            label_selector="app=ml-training"
        )

        result = []
        for job in jobs.items:
            status = "Unknown"
            if job.status.active and job.status.active > 0:
                status = "Running"
            elif job.status.succeeded and job.status.succeeded > 0:
                status = "Completed"
            elif job.status.failed and job.status.failed > 0:
                status = "Failed"

            # Apply filter
            if status_filter != "all":
                if status_filter == "running" and status != "Running":
                    continue
                if status_filter == "completed" and status != "Completed":
                    continue
                if status_filter == "failed" and status != "Failed":
                    continue

            # Calculate age
            created = job.metadata.creation_timestamp
            age = time.time() - created.timestamp()
            if age < 60:
                age_str = f"{int(age)}s"
            elif age < 3600:
                age_str = f"{int(age / 60)}m"
            elif age < 86400:
                age_str = f"{int(age / 3600)}h"
            else:
                age_str = f"{int(age / 86400)}d"

            result.append({
                "name": job.metadata.name,
                "status": status,
                "age": age_str,
                "completions": job.status.succeeded or 0
            })

        return result

    except ApiException as e:
        logger.error(f"Error listing jobs: {e}")
        raise


def delete_job(job_name: str, namespace: str):
    """Delete a job and its pods.

    Args:
        job_name: Job name
        namespace: Kubernetes namespace
    """
    batch_api, core_api = get_k8s_client()

    try:
        # Delete job
        batch_api.delete_namespaced_job(
            job_name,
            namespace,
            propagation_policy="Foreground"
        )
        logger.info(f"Deleted job: {job_name}")

        # Delete associated ConfigMap
        configmap_name = f"{job_name}-code"
        try:
            core_api.delete_namespaced_config_map(configmap_name, namespace)
            logger.info(f"Deleted ConfigMap: {configmap_name}")
        except ApiException:
            pass  # ConfigMap might not exist

    except ApiException as e:
        logger.error(f"Error deleting job: {e}")
        raise


def get_job_status(job_name: str, namespace: str) -> Dict:
    """Get detailed job status.

    Args:
        job_name: Job name
        namespace: Kubernetes namespace

    Returns:
        Dictionary with job status information
    """
    batch_api, core_api = get_k8s_client()

    try:
        job = batch_api.read_namespaced_job(job_name, namespace)

        # Get pod info
        pods = core_api.list_namespaced_pod(
            namespace,
            label_selector=f"job-name={job_name}"
        )

        pod_status = []
        for pod in pods.items:
            pod_status.append({
                "name": pod.metadata.name,
                "phase": pod.status.phase,
                "containers": [
                    {
                        "name": c.name,
                        "ready": c.ready,
                        "restart_count": c.restart_count
                    }
                    for c in (pod.status.container_statuses or [])
                ]
            })

        return {
            "name": job_name,
            "active": job.status.active or 0,
            "succeeded": job.status.succeeded or 0,
            "failed": job.status.failed or 0,
            "start_time": job.status.start_time,
            "completion_time": job.status.completion_time,
            "pods": pod_status
        }

    except ApiException as e:
        logger.error(f"Error getting job status: {e}")
        raise


def deploy_model(
    model_name: str,
    model_uri: str,
    namespace: str,
    replicas: int = 1,
    cpu: str = "500m",
    memory: str = "1Gi",
    port: int = 8080,
    env: Optional[Dict[str, str]] = None
):
    """Deploy a model as a REST API service.

    Args:
        model_name: Name of the model deployment
        model_uri: MLflow model URI (e.g., models:/my-model/1 or runs:/run-id/model)
        namespace: Kubernetes namespace
        replicas: Number of replicas
        cpu: CPU request
        memory: Memory request
        port: Service port
        env: Additional environment variables
    """
    _, core_api = get_k8s_client()
    apps_api = client.AppsV1Api()

    env = env or {}

    # Build environment variables
    env_vars = [
        client.V1EnvVar(name="MODEL_URI", value=model_uri),
        client.V1EnvVar(name="PORT", value=str(port)),
    ]
    for key, value in env.items():
        env_vars.append(client.V1EnvVar(name=key, value=value))

    # Resource requirements
    resources = client.V1ResourceRequirements(
        requests={"cpu": cpu, "memory": memory},
        limits={"cpu": cpu, "memory": memory}
    )

    # Container spec - using MLflow's built-in model serving
    container = client.V1Container(
        name="model-server",
        image="ghcr.io/mlflow/mlflow:v2.9.2",
        command=[
            "mlflow",
            "models",
            "serve",
            "--model-uri",
            model_uri,
            "--host",
            "0.0.0.0",
            "--port",
            str(port),
            "--no-conda"
        ],
        ports=[client.V1ContainerPort(container_port=port)],
        env=env_vars,
        resources=resources,
        readiness_probe=client.V1Probe(
            http_get=client.V1HTTPGetAction(
                path="/health",
                port=port
            ),
            initial_delay_seconds=30,
            period_seconds=10
        ),
        liveness_probe=client.V1Probe(
            http_get=client.V1HTTPGetAction(
                path="/health",
                port=port
            ),
            initial_delay_seconds=45,
            period_seconds=15
        )
    )

    # Pod template
    template = client.V1PodTemplateSpec(
        metadata=client.V1ObjectMeta(labels={"app": model_name, "type": "model-server"}),
        spec=client.V1PodSpec(containers=[container])
    )

    # Deployment spec
    deployment_spec = client.V1DeploymentSpec(
        replicas=replicas,
        selector=client.V1LabelSelector(match_labels={"app": model_name}),
        template=template
    )

    # Create deployment
    deployment = client.V1Deployment(
        api_version="apps/v1",
        kind="Deployment",
        metadata=client.V1ObjectMeta(name=model_name, labels={"type": "model-server"}),
        spec=deployment_spec
    )

    try:
        apps_api.create_namespaced_deployment(namespace, deployment)
        logger.info(f"Created deployment: {model_name}")
    except ApiException as e:
        if e.status == 409:  # Already exists
            apps_api.replace_namespaced_deployment(model_name, namespace, deployment)
            logger.info(f"Updated deployment: {model_name}")
        else:
            raise

    # Create service
    service = client.V1Service(
        api_version="v1",
        kind="Service",
        metadata=client.V1ObjectMeta(name=model_name, labels={"type": "model-server"}),
        spec=client.V1ServiceSpec(
            type="ClusterIP",
            selector={"app": model_name},
            ports=[client.V1ServicePort(
                port=port,
                target_port=port,
                name="http"
            )]
        )
    )

    try:
        core_api.create_namespaced_service(namespace, service)
        logger.info(f"Created service: {model_name}")
    except ApiException as e:
        if e.status == 409:  # Already exists
            core_api.replace_namespaced_service(model_name, namespace, service)
            logger.info(f"Updated service: {model_name}")
        else:
            raise


def list_model_deployments(namespace: str, status_filter: str = "all") -> List[Dict]:
    """List model deployments.

    Args:
        namespace: Kubernetes namespace
        status_filter: Filter by status (all, available, unavailable)

    Returns:
        List of deployment information dictionaries
    """
    apps_api = client.AppsV1Api()
    _, core_api = get_k8s_client()

    try:
        deployments = apps_api.list_namespaced_deployment(
            namespace,
            label_selector="type=model-server"
        )

        result = []
        for dep in deployments.items:
            replicas = dep.spec.replicas or 0
            ready_replicas = dep.status.ready_replicas or 0
            available = ready_replicas == replicas and replicas > 0

            # Apply filter
            if status_filter == "available" and not available:
                continue
            if status_filter == "unavailable" and available:
                continue

            # Get service URL
            try:
                service = core_api.read_namespaced_service(dep.metadata.name, namespace)
                cluster_ip = service.spec.cluster_ip
                port = service.spec.ports[0].port
                service_url = f"http://{cluster_ip}:{port}"
            except ApiException:
                service_url = None

            # Calculate age
            created = dep.metadata.creation_timestamp
            age = time.time() - created.timestamp()
            if age < 60:
                age_str = f"{int(age)}s"
            elif age < 3600:
                age_str = f"{int(age / 60)}m"
            elif age < 86400:
                age_str = f"{int(age / 3600)}h"
            else:
                age_str = f"{int(age / 86400)}d"

            result.append({
                "name": dep.metadata.name,
                "replicas": replicas,
                "ready_replicas": ready_replicas,
                "available": available,
                "age": age_str,
                "service_url": service_url
            })

        return result

    except ApiException as e:
        logger.error(f"Error listing deployments: {e}")
        raise


def delete_model_deployment(model_name: str, namespace: str):
    """Delete a model deployment and its service.

    Args:
        model_name: Model deployment name
        namespace: Kubernetes namespace
    """
    apps_api = client.AppsV1Api()
    _, core_api = get_k8s_client()

    try:
        # Delete deployment
        apps_api.delete_namespaced_deployment(
            model_name,
            namespace,
            propagation_policy="Foreground"
        )
        logger.info(f"Deleted deployment: {model_name}")

        # Delete service
        try:
            core_api.delete_namespaced_service(model_name, namespace)
            logger.info(f"Deleted service: {model_name}")
        except ApiException:
            pass  # Service might not exist

    except ApiException as e:
        logger.error(f"Error deleting deployment: {e}")
        raise


def get_model_service_url(model_name: str, namespace: str) -> Optional[str]:
    """Get the service URL for a model deployment.

    Args:
        model_name: Model deployment name
        namespace: Kubernetes namespace

    Returns:
        Service URL or None if not found
    """
    _, core_api = get_k8s_client()

    try:
        service = core_api.read_namespaced_service(model_name, namespace)
        cluster_ip = service.spec.cluster_ip
        port = service.spec.ports[0].port
        return f"http://{cluster_ip}:{port}"
    except ApiException:
        return None


def stream_deployment_logs(
    deployment_name: str,
    namespace: str,
    follow: bool = False,
    tail_lines: int = 50
):
    """Stream logs from a deployment.

    Args:
        deployment_name: Deployment name
        namespace: Kubernetes namespace
        follow: Whether to follow log output
        tail_lines: Number of lines to show from the end
    """
    _, core_api = get_k8s_client()

    try:
        # Find pods for deployment
        pods = core_api.list_namespaced_pod(
            namespace,
            label_selector=f"app={deployment_name}"
        )

        if not pods.items:
            logger.error(f"No pods found for deployment {deployment_name}")
            return

        # Stream logs from first pod
        pod_name = pods.items[0].metadata.name

        if follow:
            logs = core_api.read_namespaced_pod_log(
                pod_name,
                namespace,
                follow=True,
                tail_lines=tail_lines,
                _preload_content=False
            )
            for line in logs.stream():
                print(line.decode('utf-8'), end='')
        else:
            logs = core_api.read_namespaced_pod_log(
                pod_name,
                namespace,
                tail_lines=tail_lines
            )
            print(logs)

    except ApiException as e:
        logger.error(f"Error streaming logs: {e}")
        raise
