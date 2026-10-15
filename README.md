# parcial_infraestructura — Taller 8: Promoción de una misma imagen entre ambientes

**Equipo:** Estrella de Israel · **Nube:** AWS (`us-east-1`) · **Registro:** Amazon ECR · **Ejecución:** ECS Fargate · **CI/CD:** GitHub Actions

Una aplicación HTTP mínima se construye **una sola vez** por commit, se analiza con
Trivy, se publica en ECR y se **promueve por digest** (referencia inmutable) del
ambiente de `pruebas` al de `produccion`, con **aprobación manual** antes de
producción. Pruebas y producción quedan sirviendo exactamente la misma imagen,
verificable por el commit que reporta `/health` y por el digest registrado en cada
ambiente.

## Tabla de contenidos

1. [Aplicación](#aplicación-rastreador-de-lectura-horus-tracker)
2. [Arquitectura](#arquitectura)
3. [Prerrequisitos](#prerrequisitos)
4. [Infraestructura con Terraform](#infraestructura-con-terraform)
5. [Pipeline CI/CD](#pipeline-cicd)
6. [Configuración de GitHub (variables, secretos y ambientes)](#configuración-de-github)
7. [Prueba del sistema](#prueba-del-sistema)
8. [Evidencias](#evidencias)
9. [Seguridad](#seguridad)
10. [Limitaciones y mejoras futuras](#limitaciones-y-mejoras-futuras)
11. [Destrucción de recursos](#destrucción-de-recursos)

## Aplicación: rastreador de lectura (horus-tracker)

Servidor HTTP en Python (solo biblioteca estándar, sin dependencias) que sirve una
interfaz para marcar cada libro de una saga como pendiente, leyendo o leído. El
progreso se guarda en el navegador (localStorage); el contenedor no guarda estado
ni usa credenciales.

| Ruta | Respuesta |
|---|---|
| `/` | Interfaz web |
| `/health` | `{"status":"ok","app":"horus-tracker","version":"1.0.0","commit":"<sha>"}` |

El campo `commit` sale de la variable `GIT_COMMIT`, fijada **al construir la
imagen**. Sirve como prueba visible de qué commit corre en cada ambiente.

### Ejecutar sin Docker

```bash
GIT_COMMIT=$(git rev-parse HEAD) python3 app/app.py
curl http://localhost:8080/health
```

### Construir y ejecutar con Docker

```bash
docker build --build-arg GIT_COMMIT=$(git rev-parse HEAD) -t horus-tracker:local .
docker run --rm -p 8080:8080 horus-tracker:local
curl http://localhost:8080/health
```

La imagen de CI se publica en ECR como
`704932818752.dkr.ecr.us-east-1.amazonaws.com/estrella-app:<sha>` y se promueve
como `704932818752.dkr.ecr.us-east-1.amazonaws.com/estrella-app@sha256:<digest>`.

## Arquitectura

Diagrama completo (Mermaid): [`docs/arquitectura.md`](docs/arquitectura.md)

- **Amazon ECR** (`estrella-app`): registro único con tags inmutables,
  escaneo automático al subir (`scan_on_push`), cifrado KMS y política de ciclo de
  vida (conserva 20 imágenes).
- **Dos ambientes** parametrizados con `for_each` (`pruebas`, `produccion`):
  cluster ECS con **AWS Fargate** (0.25 vCPU / 512 MB, 1 tarea), **ALB** público en
  el puerto 80, grupos de seguridad de mínimo privilegio (Internet→ALB:80;
  ALB→tarea:8080; tarea→443 para ECR/CloudWatch) y logs CloudWatch (30 días).
- **GitHub Actions** asume un rol IAM vía **OIDC** (`id-token: write`, sin claves
  estáticas) y despliega en ECS la referencia por digest registrando una nueva
  revisión de la definición de tarea; Terraform ignora ese campo
  (`ignore_changes`), así que un `apply` posterior no revierte el despliegue.
- **Promoción inmutable**: pruebas y producción reciben la misma referencia
  `repo@sha256:<digest>`; no existe ningún paso que reconstruya la imagen.

## Prerrequisitos

- AWS CLI v2 con credenciales de una cuenta AWS con permisos para ECR, ECS, ELB,
  IAM, EC2 (security groups) y CloudWatch.
- Terraform >= 1.5 (probado con 1.9/1.15).
- Docker (solo para pruebas locales; el build de CI usa Buildx).
- Repositorio de GitHub con acceso de administrador para configurar
  Environments, variables y reglas de protección.

## Infraestructura con Terraform

Todo vive en [`infraestructura/`](infraestructura/). Ver
[`docs/persona1-infra.md`](docs/persona1-infra.md) para el detalle completo.

```bash
cd infraestructura
cp terraform.tfvars.example terraform.tfvars   # ajustar valores si aplica
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
terraform output        # URLs, nombres de recursos y rol OIDC
```

Variables principales ([`variables.tf`](infraestructura/variables.tf)):

| Variable | Uso |
|---|---|
| `aws_region` | Región AWS (por defecto `us-east-1`) |
| `github_repo` | `ORG/REPO`; crea el rol OIDC para GitHub Actions (opcional) |
| `existing_iam_role_arn` | Rol IAM existente para ECS (p. ej. `LabRole` en AWS Academy) |
| `create_github_oidc_provider` | `false` si el proveedor OIDC ya existe en la cuenta |
| `environments` | Mapa por ambiente: `desired_count`, `cpu`, `memory` |

Los recursos se crean con **tags** `equipo`, `proyecto` y `ambiente`
(`default_tags`) y con **límites de costo mínimos**: 0.25 vCPU / 512 MB, 1 tarea
por ambiente, sin NAT Gateway, retención de logs de 30 días.

## Pipeline CI/CD

### `Validar infraestructura` ([`.github/workflows/ci.yml`](.github/workflows/ci.yml))

Se activa con cambios en `infraestructura/**`: ejecuta `terraform fmt -check`,
`terraform validate` y **Checkov** (política en [`.checkov.yaml`](.checkov.yaml)).
Evidencia: runs en verde en el historial de
[Actions](https://github.com/DEV-ZERO-cloud/parcial_infraestructura/actions)
(la validación pasa en cada cambio de infraestructura).

### `Construir y promover imagen` ([`.github/workflows/deploy.yml`](.github/workflows/deploy.yml))

```
push a main
  → build-and-scan:  UN build con tag = SHA del commit
                     → push a ECR → confirmación del digest (describe-images)
                     → Trivy sobre la imagen por digest (bloquea con HIGH/CRITICAL)
  → deploy-testing:  despliega <ecr>/estrella-app@sha256:<digest> en ECS (pruebas)
                     → espera estabilidad → verifica digest → prueba HTTP /health
  → deploy-production: espera la APROBACIÓN MANUAL del Environment production
                     → promueve LA MISMA referencia por digest (sin rebuild)
                     → espera estabilidad → verifica digest → prueba HTTP /health
  → resumen-promocion: compara digest publicado vs confirmado en cada ambiente;
                     falla si difieren
```

| Job | Qué hace |
|---|---|
| `build-and-scan` | Construye **una sola vez**, publica en ECR con el tag del SHA, confirma el digest contra ECR y lo analiza con Trivy |
| `deploy-testing` | Registra una revisión de la definición de tarea con la imagen por digest, actualiza el servicio, espera estabilidad, verifica el digest desplegado y prueba `APP_URL/health` |
| `deploy-production` | Requiere aprobación del Environment `production` (required reviewers); promueve la misma referencia sin reconstruir y vuelve a probar `/health` |
| `resumen-promocion` | Imprime tag y digests y falla si el digest de testing o producción difiere del publicado |

**Run verde de referencia (commit `94950b4`):**
https://github.com/DEV-ZERO-cloud/parcial_infraestructura/actions/runs/38676879961

## Configuración de GitHub

Guía paso a paso: [`docs/configuracion_github.md`](docs/configuracion_github.md).

**Environments** (Settings → Environments):

| Environment | Protección |
|---|---|
| `test` | Ninguna (aloja las variables del ambiente de pruebas) |
| `production` | **Required reviewers** + branch de despliegue `main` |

**Variables** (Settings → Secrets and variables → Actions):

| Nivel | Variable | Valor usado |
|---|---|---|
| Repositorio | `AWS_BUILD_ROLE_ARN` | ARN del rol IAM que asume el build con OIDC |
| Repositorio | `AWS_REGION` | `us-east-1` |
| Repositorio | `ECR_REGISTRY` | `704932818752.dkr.ecr.us-east-1.amazonaws.com` |
| Repositorio | `ECR_REPOSITORY` | `estrella-app` |
| Environment `test` | `AWS_ROLE_ARN` | ARN del rol IAM para desplegar |
| Environment `test` | `ECS_CLUSTER` / `ECS_SERVICE` / `TASK_FAMILY` | `estrella-pruebas` / `app` / `estrella-pruebas` |
| Environment `test` | `APP_URL` | `http://estrella-pruebas-835559274.us-east-1.elb.amazonaws.com` |
| Environment `production` | `AWS_ROLE_ARN` | ARN del rol IAM para desplegar |
| Environment `production` | `ECS_CLUSTER` / `ECS_SERVICE` / `TASK_FAMILY` | `estrella-produccion` / `app` / `estrella-produccion` |
| Environment `production` | `APP_URL` | `http://estrella-produccion-1723418970.us-east-1.elb.amazonaws.com` |

**Secretos:** no se usan credenciales estáticas. La autenticación a AWS es por
OIDC (`permissions: id-token: write` en el workflow); no hay ninguna clave de
acceso guardada en el repositorio ni en los Environments.

> Nota: el rol IAM que asume GitHub Actions se creó directamente en AWS (fuera de
> Terraform); por eso `github_actions_role_arn` sale vacío en `terraform output`.

## Prueba del sistema

1. **Infraestructura**: aplicar Terraform (ver sección anterior) y guardar
   `terraform output`.
2. **Pipeline**: enviar un commit a `main` (o ejecutar el workflow manualmente).
   Esperar el build, Trivy y el despliegue en `test`; **aprobar manualmente** el
   job de producción cuando quede en espera; esperar el resumen de promoción.
3. **HTTP**: comprobar ambos ambientes:

```bash
curl http://estrella-pruebas-835559274.us-east-1.elb.amazonaws.com/health
curl http://estrella-produccion-1723418970.us-east-1.elb.amazonaws.com/health
```

Respuesta esperada en ambos (mismo commit ⇒ misma imagen promovida):

```json
{"status": "ok", "app": "horus-tracker", "version": "1.0.0", "commit": "94950b4782d2c64af67b2d68e677c57f03366697"}
```

4. **Digest**: en el log del job `resumen-promocion` están el digest publicado y
   el confirmado en cada ambiente; el job solo termina en verde si coinciden.

> Las URLs de los ALB cambian si la infraestructura se destruye y se re-crea.
> Consulta las vigentes con `terraform output app_urls` / `health_urls`.

## Evidencias

Carpeta [`docs/evidencias/`](docs/evidencias) + historial de Actions:

| Evidencia | Dónde |
|---|---|
| Run verde del pipeline completo (build → Trivy → ECR → pruebas → aprobación → producción → digests) | [Run 38676879961](https://github.com/DEV-ZERO-cloud/parcial_infraestructura/actions/runs/38676879961) |
| Cronología de deployments con la ventana de aprobación manual (~4 min) | `docs/evidencias/deployments_timeline.txt` |
| Detalle de jobs/pasos del run verde (API de GitHub) | `docs/evidencias/run_verde_38676879961.json` |
| Prueba HTTP final en ambos ambientes (mismo commit) | `docs/evidencias/http_final_ambos_ambientes.txt` |
| `terraform output` vigente (infra re-creada) | `docs/evidencias/Outputs.txt` |
| `terraform fmt` / `validate` / `plan` / `apply` / `output` (primer apply) | `docs/evidencias/terraform_*.txt` |
| Checkov (CLI y JSON) | `docs/evidencias/results_cli.txt`, `results_json.json` |
| Tags AWS aplicados a los recursos | `docs/evidencias/aws_tags.jpeg` |
| Prueba HTTP inicial (placeholder nginx antes del primer despliegue) | `docs/evidencias/http_test_inicial.txt` |
| Validación de Terraform + Checkov en CI | Runs de `Validar infraestructura` en [Actions](https://github.com/DEV-ZERO-cloud/parcial_infraestructura/actions) |

## Seguridad

- **Sin credenciales en el repositorio**: el escaneo del repo no encuentra claves
  ni tokens; `.gitignore` excluye `*.tfstate`, `*.tfvars`, `.env*`, `*.pem`,
  `*.key`. La autenticación de Actions con AWS es por **OIDC**.
- **Imagen mínima y sin secretos**: base `python:3.12-slim`, usuario no root
  (UID 10001) sin shell de login, `HEALTHCHECK` contra `/health`, estado guardado
  en el navegador; `.dockerignore` excluye `.env`, llaves, `.git` y estado de
  Terraform.
- **Trivy** bloquea el despliegue si hay vulnerabilidades HIGH o CRITICAL
  corregibles (`--exit-code 1`, `ignore-unfixed`), analizando la imagen **por
  digest**.
- **Checkov** sobre el código de Terraform con excepciones justificadas en
  [`.checkov.yaml`](.checkov.yaml) (ver justificación en
  [`docs/persona1-infra.md`](docs/persona1-infra.md)).
- **Mínimo privilegio en red**: los grupos de seguridad solo permiten
  Internet→ALB:80, ALB→tarea:8080 y salida 443 de la tarea.
- **Tags inmutables en ECR** (`IMMUTABLE`): un tag no puede reescribirse; la
  promoción usa `@sha256:<digest>`, que es inmutable por definición.

## Limitaciones y mejoras futuras

- HTTP sin TLS (no hay dominio ni certificado ACM); mejora: HTTPS con ACM + WAF.
- Ambos ambientes comparten cuenta y VPC por defecto; mejora: cuentas/VPC
  separadas con endpoints privados.
- El rol OIDC de GitHub Actions se creó manualmente; mejora: gestionarlo con
  Terraform (`github_repo` en `terraform.tfvars`).
- Estado de Terraform local; mejora: backend S3 con bloqueo DynamoDB.
- Credenciales de laboratorio temporales (AWS Academy): la infra puede
  resetearse entre sesiones y las URLs cambian al re-crear; los recursos deben
  destruirse al terminar para no incurrir en costos.
- Sin escalado automático ni alarmas; `desired_count = 1` por ambiente.
- Trivy descarta vulnerabilidades sin corrección disponible
  (`ignore-unfixed`); documentado como decisión aceptada por el equipo.

## Destrucción de recursos

```bash
cd infraestructura
terraform destroy
```

- Borra el ECR (con todas las imágenes), los clusters ECS, las definiciones de
  tarea, los **dos ALB**, grupos de seguridad y grupos de logs.
- Si el ECR se niega a borrarse por contener imágenes, el recurso ya tiene
  `force_delete = true`; si hiciera falta, re-ejecutar el `destroy`.
- **Precaución**: confirmar la cuenta con `aws sts get-caller-identity` antes de
  destruir. Los ALB son el recurso más costoso (~16–20 USD/mes cada uno si se
  dejan vivos); destruir al terminar la demostración.
- Opcional: eliminar las variables/Environments de GitHub si se archiva el
  proyecto.
