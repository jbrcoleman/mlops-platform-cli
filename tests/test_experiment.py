"""Tests for experiment command and template scaffolding."""

import pytest
import tempfile
import shutil
from pathlib import Path
from click.testing import CliRunner
from mlp.cli import cli
from mlp.utils.templates import (
    scaffold_project,
    get_template_info,
    list_templates
)


class TestTemplateScaffolding:
    """Test template scaffolding functionality."""

    def test_scaffold_simple_project(self):
        """Test creating a simple ML project."""
        with tempfile.TemporaryDirectory() as tmpdir:
            target_path = Path(tmpdir) / "test-project"

            scaffold_project("test-project", target_path, template="simple")

            # Check directory structure
            assert target_path.exists()
            assert (target_path / "train.py").exists()
            assert (target_path / "requirements.txt").exists()
            assert (target_path / "config.yaml").exists()
            assert (target_path / "README.md").exists()
            assert (target_path / ".gitignore").exists()
            assert (target_path / "data").exists()
            assert (target_path / "models").exists()

    def test_scaffold_pytorch_project(self):
        """Test creating a PyTorch project."""
        with tempfile.TemporaryDirectory() as tmpdir:
            target_path = Path(tmpdir) / "pytorch-project"

            scaffold_project("pytorch-project", target_path, template="pytorch")

            assert target_path.exists()
            assert (target_path / "train.py").exists()
            # Check that requirements.txt contains torch
            reqs = (target_path / "requirements.txt").read_text()
            assert "torch" in reqs

    def test_scaffold_tensorflow_project(self):
        """Test creating a TensorFlow project."""
        with tempfile.TemporaryDirectory() as tmpdir:
            target_path = Path(tmpdir) / "tf-project"

            scaffold_project("tf-project", target_path, template="tensorflow")

            assert target_path.exists()
            assert (target_path / "train.py").exists()
            # Check that requirements.txt contains tensorflow
            reqs = (target_path / "requirements.txt").read_text()
            assert "tensorflow" in reqs

    def test_scaffold_sklearn_project(self):
        """Test creating a scikit-learn project."""
        with tempfile.TemporaryDirectory() as tmpdir:
            target_path = Path(tmpdir) / "sklearn-project"

            scaffold_project("sklearn-project", target_path, template="sklearn")

            assert target_path.exists()
            assert (target_path / "train.py").exists()
            # Check that requirements.txt contains scikit-learn
            reqs = (target_path / "requirements.txt").read_text()
            assert "scikit-learn" in reqs

    def test_scaffold_existing_directory_without_force(self):
        """Test that scaffolding fails if directory exists without force flag."""
        with tempfile.TemporaryDirectory() as tmpdir:
            target_path = Path(tmpdir) / "existing-project"
            target_path.mkdir()

            with pytest.raises(FileExistsError):
                scaffold_project("existing-project", target_path, template="simple", force=False)

    def test_scaffold_existing_directory_with_force(self):
        """Test that scaffolding overwrites with force flag."""
        with tempfile.TemporaryDirectory() as tmpdir:
            target_path = Path(tmpdir) / "existing-project"
            target_path.mkdir()
            (target_path / "old_file.txt").write_text("old content")

            scaffold_project("existing-project", target_path, template="simple", force=True)

            # Old file should be gone
            assert not (target_path / "old_file.txt").exists()
            # New files should exist
            assert (target_path / "train.py").exists()

    def test_invalid_template(self):
        """Test that invalid template raises error."""
        with tempfile.TemporaryDirectory() as tmpdir:
            target_path = Path(tmpdir) / "test-project"

            with pytest.raises(ValueError):
                scaffold_project("test-project", target_path, template="invalid")

    def test_get_template_info(self):
        """Test getting template information."""
        info = get_template_info("pytorch")
        assert info["name"] == "PyTorch"
        assert "dependencies" in info
        assert "torch" in info["dependencies"]

    def test_list_templates(self):
        """Test listing all templates."""
        templates = list_templates()
        assert "simple" in templates
        assert "pytorch" in templates
        assert "tensorflow" in templates
        assert "sklearn" in templates


class TestExperimentCommand:
    """Test experiment CLI commands."""

    def test_experiment_help(self):
        """Test experiment command help."""
        runner = CliRunner()
        result = runner.invoke(cli, ["experiment", "--help"])
        assert result.exit_code == 0
        assert "experiment" in result.output.lower()

    def test_experiment_create_help(self):
        """Test experiment create command help."""
        runner = CliRunner()
        result = runner.invoke(cli, ["experiment", "create", "--help"])
        assert result.exit_code == 0
        assert "create" in result.output.lower()

    def test_experiment_create_simple(self):
        """Test creating a simple experiment via CLI."""
        runner = CliRunner()
        with tempfile.TemporaryDirectory() as tmpdir:
            result = runner.invoke(cli, [
                "experiment", "create", "test-exp",
                "--path", tmpdir,
                "--template", "simple"
            ])

            assert result.exit_code == 0
            project_path = Path(tmpdir) / "test-exp"
            assert project_path.exists()
            assert (project_path / "train.py").exists()

    def test_experiment_create_invalid_name(self):
        """Test that invalid experiment name is rejected."""
        runner = CliRunner()
        with tempfile.TemporaryDirectory() as tmpdir:
            result = runner.invoke(cli, [
                "experiment", "create", "Invalid Name!",  # Invalid: contains space and !
                "--path", tmpdir
            ])

            assert result.exit_code != 0

    def test_experiment_create_pytorch(self):
        """Test creating a PyTorch experiment via CLI."""
        runner = CliRunner()
        with tempfile.TemporaryDirectory() as tmpdir:
            result = runner.invoke(cli, [
                "experiment", "create", "pytorch-exp",
                "--path", tmpdir,
                "--template", "pytorch"
            ])

            assert result.exit_code == 0
            project_path = Path(tmpdir) / "pytorch-exp"
            assert (project_path / "train.py").exists()
            reqs = (project_path / "requirements.txt").read_text()
            assert "torch" in reqs

    def test_experiment_list_help(self):
        """Test experiment list command help."""
        runner = CliRunner()
        result = runner.invoke(cli, ["experiment", "list", "--help"])
        assert result.exit_code == 0
        assert "list" in result.output.lower()


class TestConfigFile:
    """Test generated config.yaml files."""

    def test_config_yaml_structure(self):
        """Test that generated config.yaml has correct structure."""
        with tempfile.TemporaryDirectory() as tmpdir:
            target_path = Path(tmpdir) / "test-project"
            scaffold_project("test-project", target_path, template="simple")

            config_path = target_path / "config.yaml"
            assert config_path.exists()

            import yaml
            config = yaml.safe_load(config_path.read_text())

            # Check structure
            assert "experiment" in config
            assert "model" in config
            assert "data" in config
            assert "training" in config
            assert "mlflow" in config

            # Check experiment fields
            assert config["experiment"]["name"] == "test-project"


class TestReadmeGeneration:
    """Test README.md generation."""

    def test_readme_contains_project_name(self):
        """Test that README contains project name."""
        with tempfile.TemporaryDirectory() as tmpdir:
            target_path = Path(tmpdir) / "my-awesome-project"
            scaffold_project("my-awesome-project", target_path, template="simple")

            readme = (target_path / "README.md").read_text()
            assert "my-awesome-project" in readme

    def test_readme_contains_usage_instructions(self):
        """Test that README contains usage instructions."""
        with tempfile.TemporaryDirectory() as tmpdir:
            target_path = Path(tmpdir) / "test-project"
            scaffold_project("test-project", target_path, template="simple")

            readme = (target_path / "README.md").read_text()
            assert "pip install" in readme
            assert "python train.py" in readme
            assert "mlp experiment run" in readme
