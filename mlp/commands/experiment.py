"""Experiment management commands for ML Platform CLI."""

import click
import os
import yaml
import subprocess
import json
from pathlib import Path
from rich.console import Console
from rich.prompt import Prompt, Confirm
from rich.table import Table
from mlp.config import Config
from mlp.utils.validators import validate_name
from mlp.utils.logger import setup_logger

console = Console()
logger = setup_logger(__name__)


def load_training_images_from_terraform():
    """Load training image URLs from Terraform outputs."""
    default_images = {
        "pytorch": os.getenv("MLP_TRAINING_IMAGE_PYTORCH", "python:3.10-slim"),
        "tensorflow": os.getenv("MLP_TRAINING_IMAGE_TENSORFLOW", "python:3.10-slim"),
        "sklearn": os.getenv("MLP_TRAINING_IMAGE_SKLEARN", "python:3.10-slim"),
        "simple": os.getenv("MLP_TRAINING_IMAGE_SKLEARN", "python:3.10-slim"),  # simple uses sklearn image
    }

    try:
        # Find terraform directory relative to this file
        terraform_dir = Path(__file__).parent.parent.parent / "terraform" / "aws"
        if not terraform_dir.exists():
            return default_images

        result = subprocess.run(
            ["terraform", "output", "-json"],
            cwd=terraform_dir,
            capture_output=True,
            text=True,
            timeout=10
        )

        if result.returncode == 0:
            outputs = json.loads(result.stdout)
            if "ecr_repository_pytorch" in outputs:
                default_images["pytorch"] = f"{outputs['ecr_repository_pytorch']['value']}:latest"
            if "ecr_repository_tensorflow" in outputs:
                default_images["tensorflow"] = f"{outputs['ecr_repository_tensorflow']['value']}:latest"
            if "ecr_repository_sklearn" in outputs:
                default_images["sklearn"] = f"{outputs['ecr_repository_sklearn']['value']}:latest"
                default_images["simple"] = f"{outputs['ecr_repository_sklearn']['value']}:latest"

    except Exception as e:
        logger.debug(f"Could not load images from Terraform: {e}")

    return default_images


# Load default training images at module level
DEFAULT_TRAINING_IMAGES = load_training_images_from_terraform()


def detect_framework(experiment_path):
    """Detect the ML framework used in an experiment."""
    experiment_path = Path(experiment_path)

    # Check for experiment.yaml
    experiment_yaml = experiment_path / "experiment.yaml"
    if experiment_yaml.exists():
        try:
            with open(experiment_yaml, 'r') as f:
                config = yaml.safe_load(f)
                if config and "framework" in config:
                    return config["framework"]
        except Exception as e:
            logger.debug(f"Could not read experiment.yaml: {e}")

    # Check requirements.txt for framework hints
    requirements_txt = experiment_path / "requirements.txt"
    if requirements_txt.exists():
        try:
            with open(requirements_txt, 'r') as f:
                content = f.read().lower()
                if "torch" in content or "pytorch" in content:
                    return "pytorch"
                elif "tensorflow" in content:
                    return "tensorflow"
        except Exception as e:
            logger.debug(f"Could not read requirements.txt: {e}")

    # Default to sklearn/simple
    return "sklearn"


@click.group(name="experiment")
@click.pass_context
def experiment(ctx):
    """Manage ML experiments: create projects and run training jobs."""
    pass


@experiment.command(name="create")
@click.argument("name", required=True)
@click.option(
    "--path",
    "-p",
    type=click.Path(),
    default=".",
    help="Directory where the experiment will be created"
)
@click.option(
    "--template",
    "-t",
    type=click.Choice(["simple", "pytorch", "tensorflow", "sklearn"]),
    default="simple",
    help="Project template to use"
)
@click.option(
    "--force",
    "-f",
    is_flag=True,
    help="Overwrite existing directory"
)
@click.pass_context
def create(ctx, name, path, template, force):
    """Create a new ML experiment project from a template.

    Creates a scaffolded ML project with:
    - Training script with best practices
    - Configuration files
    - Requirements.txt with necessary dependencies
    - DVC initialization
    - MLflow integration

    Example:
        mlp experiment create my-model --template pytorch
    """
    # Validate experiment name
    if not validate_name(name):
        console.print(
            "[bold red]Error:[/bold red] Invalid experiment name. "
            "Use lowercase alphanumeric, hyphens, and underscores (3-50 chars)"
        )
        raise click.Abort()

    # Resolve target path
    target_path = Path(path).resolve() / name

    # Check if directory exists
    if target_path.exists() and not force:
        console.print(
            f"[bold red]Error:[/bold red] Directory '{target_path}' already exists. "
            "Use --force to overwrite."
        )
        raise click.Abort()

    console.print(f"[bold blue]Creating experiment:[/bold blue] {name}")
    console.print(f"[dim]Template: {template}[/dim]")
    console.print(f"[dim]Location: {target_path}[/dim]\n")

    # Import template scaffolding
    from mlp.utils.templates import scaffold_project

    try:
        scaffold_project(name, target_path, template, force)

        console.print(f"\n[bold green]✓[/bold green] Experiment '{name}' created successfully!")
        console.print(f"\n[bold]Next steps:[/bold]")
        console.print(f"  1. cd {name}")
        console.print(f"  2. pip install -r requirements.txt")
        console.print(f"  3. Edit train.py with your model code")
        console.print(f"  4. mlp experiment run {name}")

    except Exception as e:
        logger.error(f"Failed to create experiment: {e}")
        console.print(f"[bold red]Error:[/bold red] {e}")
        raise click.Abort()


@experiment.command(name="run")
@click.argument("experiment_path", required=True, type=click.Path(exists=True))
@click.option(
    "--name",
    "-n",
    help="Job name (default: directory name)"
)
@click.option(
    "--image",
    "-i",
    default=None,
    help="Docker image to use for the training job (auto-detected by default)"
)
@click.option(
    "--cpu",
    default="1",
    help="CPU request (e.g., '2' or '500m')"
)
@click.option(
    "--memory",
    default="2Gi",
    help="Memory request (e.g., '4Gi' or '512Mi')"
)
@click.option(
    "--gpu",
    type=int,
    default=0,
    help="Number of GPUs to request"
)
@click.option(
    "--env",
    "-e",
    multiple=True,
    help="Environment variables (KEY=VALUE)"
)
@click.option(
    "--wait",
    "-w",
    is_flag=True,
    help="Wait for job to complete and stream logs"
)
@click.pass_context
def run(ctx, experiment_path, name, image, cpu, memory, gpu, env, wait):
    """Submit an ML training job to Kubernetes.

    Packages the experiment code and submits it as a Kubernetes Job.
    Integrates with MLflow for experiment tracking.

    The CLI automatically detects the ML framework (PyTorch, TensorFlow, or scikit-learn)
    and uses a pre-built custom image with all dependencies installed, significantly
    reducing job startup time and NAT gateway costs.

    Example:
        mlp experiment run ./my-model --gpu 1 --wait
        mlp experiment run ./my-model -e LEARNING_RATE=0.001 -e EPOCHS=10
        mlp experiment run ./my-model --image custom-image:latest  # Override auto-detection
    """
    config = ctx.obj['config']
    experiment_path = Path(experiment_path).resolve()

    # Determine job name
    if not name:
        name = experiment_path.name

    # Validate job name
    if not validate_name(name):
        console.print(
            "[bold red]Error:[/bold red] Invalid job name. "
            "Use lowercase alphanumeric, hyphens, and underscores (3-50 chars)"
        )
        raise click.Abort()

    # Auto-detect framework and select appropriate image if not specified
    if image is None:
        framework = detect_framework(experiment_path)
        image = DEFAULT_TRAINING_IMAGES.get(framework, DEFAULT_TRAINING_IMAGES["sklearn"])
        console.print(f"[dim]Auto-detected framework: {framework}[/dim]")
        console.print(f"[dim]Using custom image: {image}[/dim]\n")

    # Parse environment variables
    env_vars = {}
    for e in env:
        if "=" not in e:
            console.print(f"[bold red]Error:[/bold red] Invalid env var format: {e}. Use KEY=VALUE")
            raise click.Abort()
        key, value = e.split("=", 1)
        env_vars[key] = value

    # Add MLflow tracking URI to env vars
    # Use internal Kubernetes service URL for jobs running in cluster
    mlflow_uri = f"http://mlflow-server.{config.kubernetes.namespace}.svc.cluster.local:5000"
    env_vars["MLFLOW_TRACKING_URI"] = mlflow_uri
    env_vars["MLFLOW_EXPERIMENT_NAME"] = name

    # Display job configuration
    console.print(f"[bold blue]Submitting experiment:[/bold blue] {name}")
    console.print(f"[dim]Path: {experiment_path}[/dim]")
    console.print(f"[dim]Kubernetes context: {config.kubernetes.context}[/dim]")
    console.print(f"[dim]Namespace: {config.kubernetes.namespace}[/dim]\n")

    table = Table(title="Job Configuration")
    table.add_column("Resource", style="cyan")
    table.add_column("Value", style="green")

    table.add_row("Image", image)
    table.add_row("CPU", cpu)
    table.add_row("Memory", memory)
    table.add_row("GPU", str(gpu) if gpu > 0 else "None")

    console.print(table)
    console.print()

    # Show environment variables if any
    if env_vars:
        console.print("[bold]Environment Variables:[/bold]")
        for key, value in env_vars.items():
            if "MLFLOW" in key:
                console.print(f"  [dim]{key}={value}[/dim]")
            else:
                console.print(f"  {key}={value}")
        console.print()

    # Confirm submission
    if not Confirm.ask("Submit this job to Kubernetes?", default=True):
        console.print("[yellow]Job submission cancelled[/yellow]")
        return

    # Submit job to Kubernetes
    from mlp.utils.k8s import submit_training_job, wait_for_job, stream_job_logs

    try:
        console.print("[yellow]Submitting job to Kubernetes...[/yellow]")

        job_name = submit_training_job(
            name=name,
            experiment_path=experiment_path,
            image=image,
            cpu=cpu,
            memory=memory,
            gpu=gpu,
            env_vars=env_vars,
            config=config
        )

        console.print(f"[bold green]✓[/bold green] Job '{job_name}' submitted successfully!")
        console.print(f"\n[bold]Monitor job:[/bold]")
        console.print(f"  kubectl get job {job_name} -n {config.kubernetes.namespace}")
        console.print(f"  kubectl logs -f job/{job_name} -n {config.kubernetes.namespace}")
        console.print(f"\n[bold]MLflow:[/bold]")
        console.print(f"  Track experiment at: {config.mlflow.tracking_uri}")

        # Wait for job if requested
        if wait:
            console.print(f"\n[yellow]Waiting for job to start...[/yellow]")
            wait_for_job(job_name, config.kubernetes.namespace)
            console.print(f"[bold green]Job started. Streaming logs...[/bold green]\n")
            stream_job_logs(job_name, config.kubernetes.namespace)

    except Exception as e:
        logger.error(f"Failed to submit job: {e}")
        console.print(f"[bold red]Error:[/bold red] {e}")
        raise click.Abort()


@experiment.command(name="list")
@click.option(
    "--status",
    "-s",
    type=click.Choice(["all", "running", "completed", "failed"]),
    default="all",
    help="Filter by job status"
)
@click.pass_context
def list_experiments(ctx, status):
    """List ML experiment jobs running on Kubernetes.

    Shows the status of training jobs submitted via 'mlp experiment run'.
    """
    config = ctx.obj['config']

    from mlp.utils.k8s import list_jobs

    try:
        console.print(f"[bold blue]Experiments in {config.kubernetes.namespace}[/bold blue]\n")

        jobs = list_jobs(config.kubernetes.namespace, status)

        if not jobs:
            console.print("[dim]No experiments found[/dim]")
            return

        table = Table()
        table.add_column("Name", style="cyan")
        table.add_column("Status", style="green")
        table.add_column("Age", style="yellow")
        table.add_column("Completions", style="blue")

        for job in jobs:
            table.add_row(
                job["name"],
                job["status"],
                job["age"],
                f"{job['completions']}/1"
            )

        console.print(table)

    except Exception as e:
        logger.error(f"Failed to list experiments: {e}")
        console.print(f"[bold red]Error:[/bold red] {e}")
        raise click.Abort()
