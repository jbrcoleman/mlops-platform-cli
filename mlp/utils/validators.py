"""Input validation utilities."""

import re
from pathlib import Path
from typing import Optional


def validate_name(name: str) -> bool:
    """
    Validate project/model name.

    Args:
        name: Name to validate

    Returns:
        True if valid, False otherwise
    """
    # Must be alphanumeric with hyphens/underscores, 3-50 chars
    pattern = r'^[a-z0-9][a-z0-9-_]{2,49}$'
    return bool(re.match(pattern, name))


def validate_s3_uri(uri: str) -> bool:
    """
    Validate S3 URI format.

    Args:
        uri: S3 URI to validate

    Returns:
        True if valid, False otherwise
    """
    pattern = r'^s3://[a-z0-9][a-z0-9.-]{1,61}[a-z0-9](/.*)?$'
    return bool(re.match(pattern, uri))


def validate_azure_uri(uri: str) -> bool:
    """
    Validate Azure Blob Storage URI format.

    Args:
        uri: Azure URI to validate

    Returns:
        True if valid, False otherwise
    """
    pattern = r'^azure://[a-z0-9][a-z0-9-]{1,61}[a-z0-9](/.*)?$'
    return bool(re.match(pattern, uri))


def validate_k8s_context(context: str) -> bool:
    """
    Validate Kubernetes context name.

    Args:
        context: Context name to validate

    Returns:
        True if valid, False otherwise
    """
    # Simple validation - non-empty string
    return bool(context and len(context.strip()) > 0)


def validate_k8s_namespace(namespace: str) -> bool:
    """
    Validate Kubernetes namespace.

    Args:
        namespace: Namespace to validate

    Returns:
        True if valid, False otherwise
    """
    # Must be lowercase alphanumeric with hyphens, max 63 chars
    pattern = r'^[a-z0-9]([-a-z0-9]*[a-z0-9])?$'
    return bool(re.match(pattern, namespace)) and len(namespace) <= 63


def validate_path(path: str, must_exist: bool = False) -> bool:
    """
    Validate file system path.

    Args:
        path: Path to validate
        must_exist: If True, path must exist

    Returns:
        True if valid, False otherwise
    """
    try:
        p = Path(path)
        if must_exist:
            return p.exists()
        return True
    except (ValueError, OSError):
        return False


def validate_url(url: str) -> bool:
    """
    Validate URL format.

    Args:
        url: URL to validate

    Returns:
        True if valid, False otherwise
    """
    pattern = r'^https?://[^\s/$.?#].[^\s]*$'
    return bool(re.match(pattern, url))
