"""Template scaffolding utilities for ML projects."""

import shutil
from pathlib import Path
from typing import Dict, Any
from jinja2 import Environment, PackageLoader, select_autoescape
from mlp.utils.logger import setup_logger

logger = setup_logger(__name__)


def get_template_engine():
    """Get configured Jinja2 environment."""
    return Environment(
        loader=PackageLoader("mlp", "templates"),
        autoescape=select_autoescape(),
        trim_blocks=True,
        lstrip_blocks=True,
    )


def scaffold_project(
    name: str,
    target_path: Path,
    template: str = "simple",
    force: bool = False
) -> None:
    """Create a new ML project from a template.

    Args:
        name: Project name
        target_path: Directory where project will be created
        template: Template type (simple, pytorch, tensorflow, sklearn)
        force: Overwrite existing directory if True

    Raises:
        FileExistsError: If target_path exists and force is False
        ValueError: If template type is invalid
    """
    # Validate template type
    valid_templates = ["simple", "pytorch", "tensorflow", "sklearn"]
    if template not in valid_templates:
        raise ValueError(f"Invalid template: {template}. Choose from {valid_templates}")

    # Handle existing directory
    if target_path.exists():
        if not force:
            raise FileExistsError(f"Directory {target_path} already exists")
        shutil.rmtree(target_path)

    # Create directory
    target_path.mkdir(parents=True, exist_ok=True)
    logger.info(f"Created directory: {target_path}")

    # Template context
    context = {
        "project_name": name,
        "project_name_safe": name.replace("-", "_"),
        "template": template,
    }

    # Get Jinja2 environment
    env = get_template_engine()

    # Define file mappings: (template_file, output_file)
    file_mappings = [
        (f"{template}/train.py.j2", "train.py"),
        (f"{template}/requirements.txt.j2", "requirements.txt"),
        ("common/README.md.j2", "README.md"),
        ("common/.gitignore.j2", ".gitignore"),
        ("common/.dvcignore.j2", ".dvcignore"),
        ("common/config.yaml.j2", "config.yaml"),
    ]

    # Render and write files
    for template_file, output_file in file_mappings:
        try:
            template_obj = env.get_template(template_file)
            content = template_obj.render(**context)

            output_path = target_path / output_file
            output_path.parent.mkdir(parents=True, exist_ok=True)
            output_path.write_text(content)

            logger.info(f"Created: {output_file}")

        except Exception as e:
            logger.warning(f"Skipping {template_file}: {e}")

    # Create additional directories
    dirs_to_create = ["data", "models", "notebooks", "src"]
    for dir_name in dirs_to_create:
        dir_path = target_path / dir_name
        dir_path.mkdir(exist_ok=True)
        # Create .gitkeep to track empty directories
        (dir_path / ".gitkeep").touch()
        logger.info(f"Created directory: {dir_name}")

    # Initialize DVC if available
    try:
        import subprocess
        result = subprocess.run(
            ["dvc", "init"],
            cwd=target_path,
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode == 0:
            logger.info("Initialized DVC repository")
    except Exception as e:
        logger.debug(f"DVC initialization skipped: {e}")

    # Initialize git if available
    try:
        import subprocess
        result = subprocess.run(
            ["git", "init"],
            cwd=target_path,
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode == 0:
            logger.info("Initialized git repository")
    except Exception as e:
        logger.debug(f"Git initialization skipped: {e}")


def get_template_info(template: str) -> Dict[str, Any]:
    """Get information about a specific template.

    Args:
        template: Template type

    Returns:
        Dictionary with template metadata
    """
    templates = {
        "simple": {
            "name": "Simple",
            "description": "Basic Python ML project with scikit-learn",
            "dependencies": ["scikit-learn", "pandas", "numpy"],
            "use_case": "Traditional ML algorithms, quick experiments",
        },
        "pytorch": {
            "name": "PyTorch",
            "description": "Deep learning project with PyTorch",
            "dependencies": ["torch", "torchvision", "pytorch-lightning"],
            "use_case": "Neural networks, computer vision, NLP",
        },
        "tensorflow": {
            "name": "TensorFlow",
            "description": "Deep learning project with TensorFlow/Keras",
            "dependencies": ["tensorflow", "keras"],
            "use_case": "Neural networks, production deployment",
        },
        "sklearn": {
            "name": "Scikit-learn",
            "description": "Comprehensive ML project with scikit-learn",
            "dependencies": ["scikit-learn", "pandas", "numpy", "matplotlib", "seaborn"],
            "use_case": "Traditional ML with full data science stack",
        },
    }

    return templates.get(template, {})


def list_templates() -> Dict[str, Dict[str, Any]]:
    """List all available templates.

    Returns:
        Dictionary mapping template names to their metadata
    """
    return {
        "simple": get_template_info("simple"),
        "pytorch": get_template_info("pytorch"),
        "tensorflow": get_template_info("tensorflow"),
        "sklearn": get_template_info("sklearn"),
    }
