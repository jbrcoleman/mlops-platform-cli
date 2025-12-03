"""Tests for init command."""

import pytest
from pathlib import Path
from mlp.config import Config


def test_config_creation():
    """Test that Config can be created with defaults."""
    config = Config()
    assert config.kubernetes.context == "kind-mlp"
    assert config.kubernetes.namespace == "ml-platform"
    assert config.mlflow.tracking_uri == "http://localhost:5000"
    assert config.dvc.remote == "s3://mlp-data"


def test_config_model_dump():
    """Test that Config can be serialized."""
    config = Config()
    data = config.model_dump()
    assert "kubernetes" in data
    assert "mlflow" in data
    assert "dvc" in data
