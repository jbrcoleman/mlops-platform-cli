# Route53 DNS Configuration for MLflow

# Data source to look up the existing hosted zone
data "aws_route53_zone" "main" {
  count = var.domain_name != "" ? 1 : 0
  name  = var.domain_name
}

# Create CNAME record for MLflow pointing to the LoadBalancer
resource "aws_route53_record" "mlflow" {
  count   = var.domain_name != "" ? 1 : 0
  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = "${var.mlflow_subdomain}.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = [kubernetes_service.mlflow.status[0].load_balancer[0].ingress[0].hostname]

  depends_on = [
    kubernetes_service.mlflow
  ]
}
