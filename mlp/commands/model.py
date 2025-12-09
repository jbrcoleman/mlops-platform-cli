"""Model deployment and management commands."""

import click
from rich.console import Console
from rich.table import Table
from rich.prompt import Confirm
from mlp.utils.k8s import (
    deploy_model,
    list_model_deployments,
    delete_model_deployment,
    get_model_service_url
)
from mlp.utils.validators import validate_name
from mlp.utils.logger import setup_logger

logger = setup_logger(__name__)
console = Console()


@click.group()
def model():
    """Manage ML model deployments."""
    pass


@model.command(name="deploy")
@click.argument("model_name")
@click.option(
    "--model-uri",
    "-u",
    help="MLflow model URI (e.g., models:/my-model/1 or runs:/run-id/model)",
    required=True,
)
@click.option(
    "--replicas",
    "-r",
    type=int,
    default=1,
    help="Number of replicas for the deployment",
)
@click.option(
    "--cpu",
    type=str,
    default="500m",
    help="CPU request (e.g., 500m, 1)",
)
@click.option(
    "--memory",
    type=str,
    default="1Gi",
    help="Memory request (e.g., 512Mi, 1Gi)",
)
@click.option(
    "--port",
    type=int,
    default=8080,
    help="Port for the model service",
)
@click.option(
    "--env",
    "-e",
    multiple=True,
    help="Environment variables (KEY=VALUE)",
)
@click.pass_context
def deploy_cmd(ctx, model_name, model_uri, replicas, cpu, memory, port, env):
    """Deploy a trained model as a REST API endpoint.

    Example:
        mlp model deploy my-model --model-uri models:/my-model/1
        mlp model deploy my-model --model-uri runs:/abc123/model --replicas 3
    """
    config = ctx.obj['config']

    # Validate model name
    if not validate_name(model_name):
        console.print(
            "[red]✗[/red] Invalid model name. Use only lowercase letters, numbers, "
            "hyphens, and underscores (3-50 characters)."
        )
        raise click.Abort()

    # Parse environment variables
    env_dict = {}
    for e in env:
        if "=" not in e:
            console.print(f"[red]✗[/red] Invalid environment variable format: {e}")
            console.print("Use KEY=VALUE format")
            raise click.Abort()
        key, value = e.split("=", 1)
        env_dict[key] = value

    # Add MLflow tracking URI to environment
    env_dict["MLFLOW_TRACKING_URI"] = config.mlflow.tracking_uri

    # Display deployment configuration
    console.print("\n[bold]Model Deployment Configuration[/bold]")
    table = Table(show_header=False)
    table.add_column("Property", style="cyan")
    table.add_column("Value", style="white")

    table.add_row("Model Name", model_name)
    table.add_row("Model URI", model_uri)
    table.add_row("Replicas", str(replicas))
    table.add_row("CPU Request", cpu)
    table.add_row("Memory Request", memory)
    table.add_row("Service Port", str(port))
    table.add_row("Namespace", config.kubernetes.namespace)

    if env_dict:
        table.add_row("Environment", "\n".join([f"{k}={v}" for k, v in env_dict.items()]))

    console.print(table)
    console.print()

    # Confirm deployment
    if not Confirm.ask("Deploy this model?", default=True):
        console.print("[yellow]Deployment cancelled[/yellow]")
        return

    try:
        # Deploy the model
        deploy_model(
            model_name=model_name,
            model_uri=model_uri,
            namespace=config.kubernetes.namespace,
            replicas=replicas,
            cpu=cpu,
            memory=memory,
            port=port,
            env=env_dict,
        )

        console.print(f"\n[green]✓[/green] Model '{model_name}' deployed successfully!")

        # Get service URL
        service_url = get_model_service_url(model_name, config.kubernetes.namespace)
        if service_url:
            console.print(f"\n[bold]Service URL:[/bold] {service_url}")
            console.print("\nTo test the endpoint:")
            console.print(f"  curl -X POST {service_url}/invocations -H 'Content-Type: application/json' -d '{{\"data\": [[1,2,3,4]]}}'")

        console.print(f"\nTo check deployment status:")
        console.print(f"  kubectl get deployment {model_name} -n {config.kubernetes.namespace}")
        console.print(f"  kubectl get pods -l app={model_name} -n {config.kubernetes.namespace}")

    except Exception as e:
        logger.exception("Failed to deploy model")
        console.print(f"\n[red]✗[/red] Failed to deploy model: {str(e)}")
        raise click.Abort()


@model.command(name="list")
@click.option(
    "--status",
    "-s",
    type=click.Choice(["all", "available", "unavailable"]),
    default="all",
    help="Filter by availability status",
)
@click.pass_context
def list_cmd(ctx, status):
    """List deployed models.

    Example:
        mlp model list
        mlp model list --status available
    """
    config = ctx.obj['config']

    try:
        deployments = list_model_deployments(
            namespace=config.kubernetes.namespace,
            status_filter=status
        )

        if not deployments:
            console.print(f"\n[yellow]No model deployments found in namespace '{config.kubernetes.namespace}'[/yellow]")
            return

        # Display deployments table
        table = Table(title=f"\nModel Deployments (namespace: {config.kubernetes.namespace})")
        table.add_column("Name", style="cyan")
        table.add_column("Replicas", style="white")
        table.add_column("Available", style="green")
        table.add_column("Age", style="white")
        table.add_column("Service URL", style="blue")

        for dep in deployments:
            table.add_row(
                dep["name"],
                f"{dep['ready_replicas']}/{dep['replicas']}",
                "✓" if dep["available"] else "✗",
                dep["age"],
                dep["service_url"] or "N/A",
            )

        console.print(table)

    except Exception as e:
        logger.exception("Failed to list model deployments")
        console.print(f"\n[red]✗[/red] Failed to list deployments: {str(e)}")
        raise click.Abort()


@model.command(name="delete")
@click.argument("model_name")
@click.option(
    "--force",
    "-f",
    is_flag=True,
    help="Skip confirmation prompt",
)
@click.pass_context
def delete_cmd(ctx, model_name, force):
    """Delete a deployed model.

    Example:
        mlp model delete my-model
        mlp model delete my-model --force
    """
    config = ctx.obj['config']

    # Confirm deletion
    if not force:
        if not Confirm.ask(
            f"Are you sure you want to delete model deployment '{model_name}'?",
            default=False
        ):
            console.print("[yellow]Deletion cancelled[/yellow]")
            return

    try:
        delete_model_deployment(
            model_name=model_name,
            namespace=config.kubernetes.namespace
        )

        console.print(f"\n[green]✓[/green] Model deployment '{model_name}' deleted successfully!")

    except Exception as e:
        logger.exception("Failed to delete model deployment")
        console.print(f"\n[red]✗[/red] Failed to delete deployment: {str(e)}")
        raise click.Abort()


@model.command(name="logs")
@click.argument("model_name")
@click.option(
    "--follow",
    "-f",
    is_flag=True,
    help="Follow log output",
)
@click.option(
    "--tail",
    "-t",
    type=int,
    default=50,
    help="Number of lines to show from the end of logs",
)
@click.pass_context
def logs_cmd(ctx, model_name, follow, tail):
    """View logs from a deployed model.

    Example:
        mlp model logs my-model
        mlp model logs my-model --follow
    """
    config = ctx.obj['config']

    try:
        from mlp.utils.k8s import stream_deployment_logs

        console.print(f"\n[bold]Logs for model '{model_name}'[/bold]\n")

        stream_deployment_logs(
            deployment_name=model_name,
            namespace=config.kubernetes.namespace,
            follow=follow,
            tail_lines=tail
        )

    except KeyboardInterrupt:
        console.print("\n[yellow]Log streaming interrupted[/yellow]")
    except Exception as e:
        logger.exception("Failed to fetch logs")
        console.print(f"\n[red]✗[/red] Failed to fetch logs: {str(e)}")
        raise click.Abort()
