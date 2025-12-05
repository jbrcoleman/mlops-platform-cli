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
      version = "v2.9.2"
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
          version = "v2.9.2"
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
            "pip install --user --no-cache-dir mlflow==2.9.2 psycopg2-binary boto3 && export PATH=$PATH:/root/.local/bin && mlflow server --host 0.0.0.0 --port 5000 --backend-store-uri postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME --default-artifact-root s3://${aws_s3_bucket.mlflow_artifacts.id}/mlflow-artifacts --serve-artifacts --gunicorn-opts '--workers=2 --timeout=120'"
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
            run_as_non_root             = false
            run_as_user                 = 0  # Run as root to allow pip install
            allow_privilege_escalation  = false
            read_only_root_filesystem   = false
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
    aws_db_instance.mlflow
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
    }
  }

  spec {
    type = "LoadBalancer"

    selector = {
      app = "mlflow-server"
    }

    port {
      name        = "http"
      port        = 5000
      target_port = 5000
      protocol    = "TCP"
    }

    session_affinity = "ClientIP"
  }

  depends_on = [
    kubernetes_deployment.mlflow
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
        stabilization_window_seconds = 300
        policy {
          type          = "Percent"
          value         = 50
          period_seconds = 60
        }
      }
      scale_up {
        stabilization_window_seconds = 0
        policy {
          type          = "Percent"
          value         = 100
          period_seconds = 30
        }
      }
    }
  }

  depends_on = [
    kubernetes_deployment.mlflow
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
    kubernetes_deployment.mlflow
  ]
}

# Output MLflow service URL
output "mlflow_service_hostname" {
  description = "MLflow LoadBalancer hostname"
  value       = try(kubernetes_service.mlflow.status[0].load_balancer[0].ingress[0].hostname, "pending")
}
