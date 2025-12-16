# MLflow Kubernetes Deployment

# Kubernetes Secret for RDS Credentials
resource "kubernetes_secret" "mlflow_db" {
  metadata {
    name      = "mlflow-db-secret"
    namespace = kubernetes_namespace.ml_platform.metadata[0].name
  }

  data = {
    username = var.rds_master_username
    password = random_password.rds_master_password.result
    database = var.rds_database_name
    host     = aws_db_instance.mlflow.address
    port     = tostring(aws_db_instance.mlflow.port)
  }

  type = "Opaque"

  depends_on = [
    aws_db_instance.mlflow
  ]
}

# MLflow Deployment
resource "kubernetes_deployment" "mlflow" {
  metadata {
    name      = "mlflow-server"
    namespace = kubernetes_namespace.ml_platform.metadata[0].name

    labels = {
      app     = "mlflow-server"
      version = "v3.7.0"
    }
  }

  spec {
    replicas = var.mlflow_replicas

    selector {
      match_labels = {
        app = "mlflow-server"
      }
    }

    template {
      metadata {
        labels = {
          app     = "mlflow-server"
          version = "v3.7.0"
        }

        annotations = {
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "5000"
          "prometheus.io/path"   = "/metrics"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.mlflow.metadata[0].name

        # Init container to wait for RDS
        init_container {
          name  = "wait-for-db"
          image = "postgres:15-alpine"

          command = [
            "sh",
            "-c",
            "until pg_isready -h $(DB_HOST) -p $(DB_PORT) -U $(DB_USER); do echo waiting for database; sleep 2; done;"
          ]

          env {
            name = "DB_HOST"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.mlflow_db.metadata[0].name
                key  = "host"
              }
            }
          }

          env {
            name = "DB_PORT"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.mlflow_db.metadata[0].name
                key  = "port"
              }
            }
          }

          env {
            name = "DB_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.mlflow_db.metadata[0].name
                key  = "username"
              }
            }
          }
        }

        container {
          name  = "mlflow"
          image = var.mlflow_image

          command = ["sh", "-c"]

          args = [
            <<-EOT
              python3 -c "from urllib.parse import quote_plus; import os; print('postgresql://{}:{}@{}:{}/{}'.format(os.environ['DB_USER'], quote_plus(os.environ['DB_PASSWORD']), os.environ['DB_HOST'], os.environ['DB_PORT'], os.environ['DB_NAME']))" > /tmp/db_uri.txt && \
              mlflow server --host 0.0.0.0 --port 5000 \
                --backend-store-uri $(cat /tmp/db_uri.txt) \
                --default-artifact-root s3://${aws_s3_bucket.mlflow_artifacts.id}/mlflow-artifacts \
                --serve-artifacts \
                --allowed-hosts 'mlflow-server.${var.k8s_namespace}.svc.cluster.local:5000' \
                --allowed-hosts 'mlflow-server:5000' \
                --allowed-hosts 'localhost:5000' \
                --allowed-hosts '127.0.0.1:5000' \
                --allowed-hosts '${var.mlflow_subdomain}.${var.domain_name}:5000' \
                --allowed-hosts '*'
            EOT
          ]

          # Environment variables
          env {
            name = "DB_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.mlflow_db.metadata[0].name
                key  = "username"
              }
            }
          }

          env {
            name = "DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.mlflow_db.metadata[0].name
                key  = "password"
              }
            }
          }

          env {
            name = "DB_HOST"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.mlflow_db.metadata[0].name
                key  = "host"
              }
            }
          }

          env {
            name = "DB_PORT"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.mlflow_db.metadata[0].name
                key  = "port"
              }
            }
          }

          env {
            name = "DB_NAME"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.mlflow_db.metadata[0].name
                key  = "database"
              }
            }
          }

          env {
            name  = "AWS_DEFAULT_REGION"
            value = var.aws_region
          }

          # Port
          port {
            container_port = 5000
            name           = "http"
            protocol       = "TCP"
          }

          # Probes
          liveness_probe {
            http_get {
              path = "/health"
              port = 5000
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 5000
            }
            initial_delay_seconds = 15
            period_seconds        = 5
            timeout_seconds       = 3
            failure_threshold     = 3
          }

          # Resources
          resources {
            requests = {
              cpu    = var.mlflow_cpu_request
              memory = var.mlflow_memory_request
            }
            limits = {
              cpu    = var.mlflow_cpu_limit
              memory = var.mlflow_memory_limit
            }
          }

          # Security context
          security_context {
            run_as_non_root            = false
            run_as_user                = 0 # Run as root to allow pip install
            allow_privilege_escalation = false
            read_only_root_filesystem  = false
          }
        }

        # Pod security
        security_context {
          fs_group = 1000
        }
      }
    }

    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_surge       = "1"
        max_unavailable = "0"
      }
    }
  }

  depends_on = [
    kubernetes_secret.mlflow_db,
    aws_db_instance.mlflow,
    module.eks
  ]
}

# MLflow Service
resource "kubernetes_service" "mlflow" {
  metadata {
    name      = "mlflow-server"
    namespace = kubernetes_namespace.ml_platform.metadata[0].name

    labels = {
      app = "mlflow-server"
    }

    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-ssl-cert"    = "arn:aws:acm:us-east-1:296592524620:certificate/205aec49-0748-4f21-ba92-8ed60a90dc0f"
      "service.beta.kubernetes.io/aws-load-balancer-ssl-ports"   = "443"
      "service.beta.kubernetes.io/aws-load-balancer-backend-protocol" = "http"
      "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
      "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
    }
  }
  spec {
    type = "LoadBalancer"

    selector = {
      app = "mlflow-server"
    }

    port {
      name        = "https"
      port        = 443
      target_port = 5000
      protocol    = "TCP"
    }

    port {
      name        = "http"
      port        = 5000
      target_port = 5000
      protocol    = "TCP"
    }
  }

  depends_on = [
    kubernetes_deployment.mlflow,
    module.eks
  ]
}

# Horizontal Pod Autoscaler for MLflow
resource "kubernetes_horizontal_pod_autoscaler_v2" "mlflow" {
  metadata {
    name      = "mlflow-server-hpa"
    namespace = kubernetes_namespace.ml_platform.metadata[0].name
  }

  spec {
    min_replicas = var.mlflow_replicas
    max_replicas = var.mlflow_replicas * 2

    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.mlflow.metadata[0].name
    }

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }

    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type                = "Utilization"
          average_utilization = 80
        }
      }
    }

    behavior {
      scale_down {
        select_policy                = "Max"
        stabilization_window_seconds = 300
        policy {
          type           = "Percent"
          value          = 50
          period_seconds = 60
        }
      }
      scale_up {
        select_policy                = "Max"
        stabilization_window_seconds = 0
        policy {
          type           = "Percent"
          value          = 100
          period_seconds = 30
        }
      }
    }
  }

  depends_on = [
    kubernetes_deployment.mlflow,
    module.eks
  ]
}

# Pod Disruption Budget for high availability
resource "kubernetes_pod_disruption_budget_v1" "mlflow" {
  metadata {
    name      = "mlflow-server-pdb"
    namespace = kubernetes_namespace.ml_platform.metadata[0].name
  }

  spec {
    min_available = 1

    selector {
      match_labels = {
        app = "mlflow-server"
      }
    }
  }

  depends_on = [
    kubernetes_deployment.mlflow,
    module.eks
  ]
}

# Wait time for AWS to clean up LoadBalancer resources (NLBs, ENIs) during destroy
# This prevents VPC destruction failures due to lingering network interfaces
resource "time_sleep" "wait_for_lb_cleanup" {
  # This resource does nothing on create, but adds a delay on destroy
  create_duration = "0s"
  destroy_duration = "90s"

  # Ensure this waits for the LoadBalancer service to be destroyed first
  depends_on = [
    kubernetes_service.mlflow
  ]

  triggers = {
    # Recreate if service changes to ensure destroy timing is updated
    service_name = kubernetes_service.mlflow.metadata[0].name
    namespace    = kubernetes_service.mlflow.metadata[0].namespace
  }
}

# Output MLflow service URL
output "mlflow_service_hostname" {
  description = "MLflow LoadBalancer hostname"
  value       = try(kubernetes_service.mlflow.status[0].load_balancer[0].ingress[0].hostname, "pending")
}
