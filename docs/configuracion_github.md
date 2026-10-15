# Configuración de GitHub para el pipeline CI/CD

Elementos de GitHub que necesita el workflow
`Construir y promover imagen` ([`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml)).
Todo esto ya está configurado en el repositorio y verificado con el run verde
[#38676879961](https://github.com/DEV-ZERO-cloud/parcial_infraestructura/actions/runs/38676879961).

## 1. Environments

Creados en **Settings → Environments**:

| Environment | Protección | Estado |
|---|---|---|
| `test` | Ninguna | Creado ✅ |
| `production` | **Required reviewers** + deployment branch policy (`main`) | Creado ✅ con protección activada |

Con la regla de revisores requeridos, el job `deploy-production` queda en
*Waiting for a required reviewer* hasta que un integrante aprueba; el workflow
nunca se auto-aprueba. En la cronología de deployments
(`docs/evidencias/deployments_timeline.txt`) se aprecia la ventana de ~4 minutos
entre el fin del despliegue en `test` y la puesta en cola de `production`.

## 2. Autenticación con AWS (OIDC, sin secretos estáticos)

El workflow declara `permissions: id-token: write` y cada job usa
`aws-actions/configure-aws-credentials@v4` con `role-to-assume`. GitHub Actions
intercambia el token OIDC por credenciales temporales de AWS; **no hay claves de
acceso guardadas** en el repositorio ni en los Environments.

El rol IAM que asume GitHub Actions fue creado directamente en AWS (confía en el
proveedor OIDC `token.actions.githubusercontent.com` con
`sub: repo:DEV-ZERO-cloud/parcial_infraestructura:*`) y no está gestionado por
Terraform; por eso `github_actions_role_arn` sale vacío en `terraform output`.
Si se quisiera gestionar con Terraform, basta definir `github_repo` en
`terraform.tfvars`.

## 3. Variables de Actions

No se usan *secrets* de AWS; solo variables. Valores vigentes:

**Nivel repositorio** (Settings → Secrets and variables → Actions → Variables):

| Variable | Valor |
|---|---|
| `AWS_BUILD_ROLE_ARN` | ARN del rol IAM para el job `build-and-scan` |
| `AWS_REGION` | `us-east-1` |
| `ECR_REGISTRY` | `704932818752.dkr.ecr.us-east-1.amazonaws.com` |
| `ECR_REPOSITORY` | `estrella-app` |

**Nivel environment `test`** (Settings → Environments → test → Variables):

| Variable | Valor |
|---|---|
| `AWS_ROLE_ARN` | ARN del rol IAM para desplegar |
| `ECS_CLUSTER` | `estrella-pruebas` |
| `ECS_SERVICE` | `app` |
| `TASK_FAMILY` | `estrella-pruebas` |
| `APP_URL` | `http://estrella-pruebas-835559274.us-east-1.elb.amazonaws.com` |

**Nivel environment `production`**:

| Variable | Valor |
|---|---|
| `AWS_ROLE_ARN` | ARN del rol IAM para desplegar |
| `ECS_CLUSTER` | `estrella-produccion` |
| `ECS_SERVICE` | `app` |
| `TASK_FAMILY` | `estrella-produccion` |
| `APP_URL` | `http://estrella-produccion-1723418970.us-east-1.elb.amazonaws.com` |

> Si la infraestructura se destruye y se re-crea, las URLs de los ALB cambian:
  actualizar `APP_URL` en ambos Environments con el nuevo
  `terraform output health_urls` (sin el `/health`, el workflow lo añade).

Comandos equivalentes con `gh` (si se usa la CLI):

```bash
gh variable set AWS_REGION --body us-east-1
gh variable set ECR_REGISTRY --body 704932818752.dkr.ecr.us-east-1.amazonaws.com
gh variable set ECR_REPOSITORY --body estrella-app
gh variable set AWS_BUILD_ROLE_ARN --body "<arn del rol>"

gh variable set AWS_ROLE_ARN --env test --body "<arn del rol>"
gh variable set ECS_CLUSTER  --env test --body estrella-pruebas
gh variable set ECS_SERVICE --env test --body app
gh variable set TASK_FAMILY  --env test --body estrella-pruebas
gh variable set APP_URL      --env test --body "<url base de pruebas>"

gh variable set AWS_ROLE_ARN --env production --body "<arn del rol>"
gh variable set ECS_CLUSTER  --env production --body estrella-produccion
gh variable set ECS_SERVICE --env production --body app
gh variable set TASK_FAMILY  --env production --body estrella-produccion
gh variable set APP_URL      --env production --body "<url base de produccion>"
```

## 4. Activación y ejecución del pipeline

El workflow se dispara con cada push a `main` y también manualmente:

```bash
gh workflow run deploy.yml
```

Secuencia esperada: `build-and-scan` → `deploy-testing` → **espera de
aprobación** → `deploy-production` → `resumen-promocion`. Al aprobar, un
integrante pulsa **Review deployments** en la página del run (o en la pestaña
de Environments).

## 5. Qué verificar tras cada ejecución

1. Un único build; el tag publicado es el SHA del commit y Trivy pasa sin
   hallazgos HIGH/CRITICAL.
2. `deploy-testing` termina en verde con la prueba HTTP exitosa.
3. El job de producción queda esperando revisor y nadie lo aprueba solo.
4. `resumen-promocion` imprime digest publicado, digest de testing y digest de
   producción, y termina en verde solo si los tres coinciden.
5. `curl <APP_URL>/health` responde el commit del build en ambos ambientes.
