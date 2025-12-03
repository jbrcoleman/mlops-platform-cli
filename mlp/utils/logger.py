"""Logging utilities using Rich console."""

import logging
from rich.console import Console
from rich.logging import RichHandler

console = Console()


def setup_logger(name: str, level: int = logging.INFO) -> logging.Logger:
    """
    Set up a logger with Rich handler for beautiful output.

    Args:
        name: Logger name
        level: Logging level (default: INFO)

    Returns:
        Configured logger instance
    """
    logger = logging.getLogger(name)
    logger.setLevel(level)

    # Add Rich handler if not already present
    if not logger.handlers:
        handler = RichHandler(
            console=console,
            rich_tracebacks=True,
            tracebacks_show_locals=True
        )
        handler.setFormatter(logging.Formatter("%(message)s"))
        logger.addHandler(handler)

    return logger


def get_logger(name: str) -> logging.Logger:
    """
    Get or create a logger.

    Args:
        name: Logger name

    Returns:
        Logger instance
    """
    return setup_logger(name)
