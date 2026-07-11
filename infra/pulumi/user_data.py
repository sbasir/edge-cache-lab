"""User-data script builder EC2 instance."""

from utils import load_template_source, render_template


def build_user_data(aws_region: str, scripts_bucket: str) -> str:
    """Return the cloud-init script used to bootstrap the instance.

    Parameters
    ----------
    aws_region: AWS region for SSM parameter store access.
    scripts_bucket: S3 bucket name containing bootstrap scripts.
    """

    if not scripts_bucket:
        raise ValueError("scripts_bucket must be a non-empty string.")

    context = {
        "scripts_bucket": scripts_bucket,
        "cloudwatch_agent_config": load_template_source(
            "cloudwatch-agent-config.json",
        ),
        "aws_region": aws_region,
    }
    return render_template("cloud-config.yaml.j2", context)
