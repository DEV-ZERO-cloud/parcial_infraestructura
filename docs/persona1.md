*(Sincronizado con la carpeta `infraestructura/` y con el contrato exacto para Persona 2 y Persona 3)*:

# Persona 1: Infraestructura como código (AWS)

Arquitectura: **Amazon ECR** (registro único) + **ECS Fargate** con un **Application Load Balancer** por ambiente (`pruebas` y `produccion`). ECS despliega la imagen por digest (`repo@sha256:...`), cumpliendo el requisito central del Taller 8.

## Qué crea Terraform (`infraestructura/`)
- 1 repositorio ECR (`estrella-app`): tags inmutables, escaneo al subir, cifrado KMS, `force_delete = true` y política de ciclo de vida (conserva las últimas 20 imágenes).
- Por ambiente (`for_each` sobre `pruebas` y `produccion`, sin duplicar código): cluster ECS, servicio Fargate (`256` CPU / `512` MB, 1 tarea), definición de tarea, ALB público en el puerto 80, grupo de destino (puerto 8080), grupos de seguridad con mínimo privilegio, grupo de logs en CloudWatch (30 días) y dos roles IAM (ejecución y tarea).
- Rol OIDC `estrella-github-actions` para GitHub Actions (cuando se define `github_repo`), con permisos mínimos sobre ECR, ECS e `iam:PassRole`.
- Tags obligatorios en todos los recursos: `equipo`, `proyecto` y `ambiente`.

## Paso a paso de ejecución

### 1. Inicializar, formatear y validar
```bash
cd infraestructura
cp terraform.tfvars.example terraform.tfvars
# Editar terraform.tfvars con github_repo = "USUARIO_O_ORG/NOMBRE_REPO"
terraform init
terraform fmt -check -recursive
terraform validate