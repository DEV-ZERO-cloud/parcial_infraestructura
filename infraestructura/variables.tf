variable "aws_region" {
  description = "Región de AWS donde se despliegan los recursos."
  type        = string
  default     = "us-east-1"
}

variable "team" {
  description = "Nombre del equipo (tag obligatorio)."
  type        = string
  default     = "estrella-de-israel"
}

variable "project" {
  description = "Nombre del proyecto (tag obligatorio)."
  type        = string
  default     = "taller8-promocion-imagen"
}

variable "ecr_repository_name" {
  description = "Nombre del repositorio ECR donde CI publica la imagen."
  type        = string
  default     = "estrella-app"
}

variable "target_port" {
  description = "Puerto en el que escucha la aplicación dentro del contenedor (coincide con el Dockerfile de Persona 2)."
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "Ruta que usa el balanceador para comprobar salud. Usa '/' inicialmente por compatibilidad con el placeholder y la interfaz web."
  type        = string
  default     = "/"
}

variable "placeholder_image" {
  description = "Imagen pública inicial sin privilegios en puerto 8080. CI/CD la reemplaza por la imagen de ECR identificada por digest."
  type        = string
  default     = "public.ecr.aws/nginx/nginx-unprivileged:stable"
}

variable "github_repo" {
  description = "Repositorio de GitHub en formato ORG/REPO. Si se define y no se usa LabRole, se crea el rol OIDC para GitHub Actions."
  type        = string
  default     = ""
}

variable "create_github_oidc_provider" {
  description = "Crear el proveedor OIDC de GitHub en la cuenta. Poner false si ya existe en la cuenta de AWS."
  type        = bool
  default     = true
}

variable "existing_iam_role_arn" {
  description = "ARN de un rol IAM existente para ECS (ej. arn:aws:iam::<ACCOUNT_ID>:role/LabRole en AWS Academy). Dejar vacío en cuentas AWS estándar para que Terraform cree los roles de mínimo privilegio."
  type        = string
  default     = ""
}

variable "environments" {
  description = "Ambientes a crear (pruebas y produccion). Se parametrizan para evitar duplicar código."
  type = map(object({
    desired_count = number
    cpu           = number
    memory        = number
  }))
  default = {
    pruebas = {
      desired_count = 1
      cpu           = 256
      memory        = 512
    }
    produccion = {
      desired_count = 1
      cpu           = 256
      memory        = 512
    }
  }
}