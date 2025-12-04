"""Main CLI entry point for ML Platform CLI."""

import click
from rich.console import Console
from mlp.config import Config

console = Console()


@click.group()
@click.version_option(version="0.1.0")
@click.pass_context
def cli(ctx):
    """ML Platform CLI - Simplify your MLOps workflows."""
    ctx.ensure_object(dict)
    # Load config from ~/.mlp/config.yaml
    ctx.obj['config'] = Config.load()


# Import and register commands
# We'll add these as we create them
from mlp.commands import init, experiment

cli.add_command(init.init_cmd)
cli.add_command(experiment.experiment)

# Future command groups (to be added later):
# cli.add_command(model.model)
# cli.add_command(data.data)
# cli.add_command(pipeline.pipeline)
# cli.add_command(monitor.monitor)
# cli.add_command(cost.cost)


if __name__ == "__main__":
    cli()
