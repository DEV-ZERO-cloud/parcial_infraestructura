# Persona 1: Infraestructura como código (AWS)

Arquitectura: **Amazon ECR** (registro único) + **ECS Fargate** con un **Application Load Balancer** por ambiente (`pruebas` y `produccion`). ECS permite desplegar la imagen por digest (`repo@sha256:...`), que es el centro del Taller 8.

## Qué crea Terraform

- 1 repositorio ECR (`estrella-app`): tags inmutables, escaneo al subir, cifrado KMS, conserva las últimas 20 imágenes.
- Por ambiente (con `for_each`, sin duplicar código): cluster ECS, servicio Fargate, definición de tarea, ALB público en el puerto 80, grupo de destino, grupos de seguridad, grupo de logs (30 días) y dos roles IAM (ejecución y tarea, la tarea sin permisos).
- Opcional: rol OIDC `estrella-github-actions` para GitHub Actions (si defines `github_repo`), con permisos mínimos: subir a ECR, registrar tarea, actualizar el servicio y `iam:PassRole` solo de los roles de la app.
- Tags en todo: `equipo`, `proyecto`, `ambiente` (los dos primeros por `default_tags`).
- Costos: 0.25 vCPU / 0.5 GB, 1 tarea por ambiente, sin NAT Gateway (IP pública en la tarea). Lo más caro son los dos ALB (aprox. 16-20 USD/mes cada uno, pero solo se cobra el tiempo que existan). **Destruye al terminar.**
- Se usa la VPC por defecto de la cuenta para no complicar el taller.

## Paso a paso

### 0. Prerrequisitos
1. Instalar AWS CLI v2 y Terraform >= 1.5.
2. Configurar credenciales con permisos para crear ECR, ECS, ELB, IAM, EC2 (grupos de seguridad) y CloudWatch (en el taller se suelen usar `aws configure` o SSO; si usan AWS Academy/Learner Lab, ver la nota al final).
3. Verificar: `aws sts get-caller-identity`.

### 1. Inicializar y validar
```
cd infra
cp terraform.tfvars.example terraform.tfvars   # editar github_repo = "ORG/REPO"
terraform init
terraform fmt -recursive
terraform validate
```
Guarda la salida (o captura) en `docs/evidencias/`.

### 2. Checkov
Desde la raíz del repositorio:
```
pip install checkov
checkov --config-file .checkov.yaml --output cli --output json --output-file-path docs/evidencias/
```
Si aparece un fallo que no está en las excepciones, corrígelo o añádelo a `.checkov.yaml` con su justificación. Guarda la salida como evidencia.

### 3. Aplicar
```
cd infra
terraform plan -out=tfplan
terraform apply tfplan
terraform output
```
Captura `terraform apply` y `terraform output` (evidencia de infraestructura aplicada). Las apps arrancan con una imagen nginx pública de relleno; CI/CD la reemplaza. Espera 2-3 minutos y abre cada URL de `app_urls` para comprobar que responden.

### 4. Entregar datos a las demás personas
Comparte la salida de `terraform output`:
- `ecr_repository_url` y `ecr_repository_name` (la imagen será `<url>:<sha>`)
- `ecs_clusters`, `ecs_services` y `task_definition_families` (claves `pruebas` y `produccion`)
- `app_urls` (para la prueba HTTP)
- `github_actions_role_arn` (secret/variable `AWS_ROLE_ARN`) y `aws_region`
- La app debe escuchar en el puerto **8080** y responder 2xx en `/` (health check del balanceador; `/health` también debe existir para la prueba HTTP).

### 5. Cómo despliega CI/CD (para Persona 3)
Con el rol OIDC (`aws-actions/configure-aws-credentials` con `role-to-assume`), el workflow debe:
1. Obtener el digest: `aws ecr describe-images --repository-name estrella-app --image-ids imageTag=<sha> --query 'imageDetails[0].imageDigest' --output text`
2. Descargar la definición actual: `aws ecs describe-task-definition --task-definition estrella-pruebas --query taskDefinition`, cambiar `containerDefinitions[0].image` a `<ecr_repository_url>@sha256:<digest>`, registrarla (`aws ecs register-task-definition`) y actualizar el servicio (`aws ecs update-service --cluster estrella-pruebas --service app --task-definition <nueva>`).
3. Repetir lo mismo con `estrella-produccion` usando **el mismo digest**, solo después de la aprobación.

Terraform ignora la imagen y la definición de tarea (`ignore_changes`), así que un `apply` posterior no revierte lo que despliega CI/CD. Los permisos del rol OIDC ya cubren estos pasos.

### 6. Destrucción
```
cd infra
terraform destroy
```
Precaución: borra el ECR con todas las imágenes, los dos ambientes y los ALB. Si el ECR no se deja borrar por contener imágenes, añade `force_delete = true` al recurso `aws_ecr_repository` y repite. Confirma que estás en la cuenta correcta.

## Excepciones de Checkov (justificación para el README)
El ALB sirve HTTP (no hay dominio ni certificado), sin logs de acceso ni WAF, y las tareas llevan IP pública para evitar el costo de un NAT. Se usa retención de logs de 30 días por costo. Ver `.checkov.yaml` para la lista exacta.

## Limitaciones y mejoras futuras
- HTTP sin cifrado: mejora con dominio, certificado ACM y listener HTTPS.
- Estado de Terraform local: mejora con backend S3 y bloqueo.
- Pruebas y producción comparten cuenta, VPC por defecto y repositorio ECR; mejora con cuentas separadas, VPC propia con subredes privadas y NAT/VPC endpoints.
- Sin WAF ni escalado automático.

## Nota: AWS Academy / Learner Lab
Esos entornos no permiten crear roles IAM ni proveedores OIDC y entregan credenciales temporales. Si es su caso, avísame para ajustar: usar el rol `LabRole` existente y secrets de GitHub en lugar de OIDC.

## Checklist de Persona 1
- [ ] `terraform fmt` y `validate` sin errores (evidencia guardada)
- [ ] Checkov ejecutado y salida guardada
- [ ] `terraform apply` hecho y captura de `terraform output`
- [ ] Salidas compartidas con Personas 2, 3 y 4
- [ ] Tags verificados en la consola de AWS
- [ ] Procedimiento de destrucción documentado en el README
