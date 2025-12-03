"""Initialize ML Platform CLI configuration."""

import click
from rich.console import Console
from rich.prompt import Prompt, Confirm
from mlp.config import Config

console = Console()


@click.command(name="init")
@click.pass_context
def init_cmd(ctx):
    """Initialize ML Platform CLI configuration."""
    console.print("[bold blue]ML Platform CLI Setup[/bold blue]")
    console.print()

    config = Config()

    # Kubernetes setup
    console.print("[bold]Kubernetes Configuration[/bold]")
    config.kubernetes.context = Prompt.ask(
        "Kubernetes context",
        default=config.kubernetes.context
    )
    config.kubernetes.namespace = Prompt.ask(
        "Default namespace",
        default=config.kubernetes.namespace
    )

    # MLflow setup
    console.print("\n[bold]MLflow Configuration[/bold]")
    config.mlflow.tracking_uri = Prompt.ask(
        "MLflow tracking URI",
        default=config.mlflow.tracking_uri
    )

    # DVC setup
    console.print("\n[bold]DVC Configuration[/bold]")
    config.dvc.remote = Prompt.ask(
        "DVC remote (s3://bucket or azure://container)",
        default=config.dvc.remote
    )

    # Save config
    config.save()
    console.print("\n[bold green]✓[/bold green] Configuration saved to ~/.mlp/config.yaml")

    # Offer to deploy infrastructure
    if Confirm.ask("\nDeploy local infrastructure (kind cluster + MLflow)?"):
        console.print("[yellow]Infrastructure deployment coming in Week 2![/yellow]")
        console.print("[dim]Run 'mlp deploy-local' when available[/dim]")
