# Configuración de GitHub para el pipeline CI/CD

Guía para configurar los elementos de GitHub que necesita el workflow
`Construir y promover imagen` (`.github/workflows/deploy.yml`). No requiere
infraestructura de nube: se puede completar en cualquier momento y queda
lista para cuando exista el adaptador de despliegue real.

## 1. Activación de los despliegues

Los jobs `deploy-testing`, `deploy-production` y `resumen-promocion` solo se
ejecutan cuando la variable de repositorio `DEPLOY_ADAPTER_READY` vale
`true`. Mientras no esté definida, cada run construye, analiza con Trivy y
publica la imagen, y los despliegues quedan omitidos (*skipped*) sin marcar
el run como fallido.

Para activar los despliegues cuando la infraestructura esté lista:

```bash
gh variable set DEPLOY_ADAPTER_READY --body true
```

Alternativa en la interfaz: **Settings → Secrets and variables → Actions →
Variables → New repository variable**, nombre `DEPLOY_ADAPTER_READY` y valor
`true`.

Para desactivarlos temporalmente (por ejemplo, para proteger la cuenta de
nube durante la demostración):

```bash
gh variable set DEPLOY_ADAPTER_READY --body false
```

## 2. Environments

Crear ambos en **Settings → Environments → New environment**.

### `testing`

Sin reglas de protección: solo aloja los secretos y la variable del ambiente.

### `production`

1. En **Deployment protection rules**, activar **Required reviewers** y
   agregar a los integrantes del equipo.
2. En **Deployment branch policy**, restringir los despliegues a `main`.

Con esto, el job `deploy-production` queda en estado *Waiting for a required
reviewer* hasta que alguien aprueba. La aprobación se configura en GitHub;
el workflow nunca se auto-aprueba.

> Los environments también se pueden crear con la API:
> `gh api -X POST repos/<owner>/<repo>/environments/production`.
> Las reglas de protección se configuran desde la interfaz.

## 3. Secretos y variables por ambiente

| Tipo | Nombre | Ambiente | Uso |
|---|---|---|---|
| Secret | `DEPLOY_WEBHOOK_URL` | testing y production | URL HTTPS del adaptador de despliegue del ambiente |
| Secret | `DEPLOY_WEBHOOK_TOKEN` | testing y production | Token bearer del adaptador |
| Variable | `HEALTH_URL` | testing y production | URL pública de `/health` del ambiente |

Comandos equivalentes con `gh`:

```bash
# testing
gh secret set DEPLOY_WEBHOOK_URL --env testing --body "<url del adaptador>"
gh secret set DEPLOY_WEBHOOK_TOKEN --env testing --body "<token>"
gh variable set HEALTH_URL --env testing --body "<url>/health"

# production
gh secret set DEPLOY_WEBHOOK_URL --env production --body "<url del adaptador>"
gh secret set DEPLOY_WEBHOOK_TOKEN --env production --body "<token>"
gh variable set HEALTH_URL --env production --body "<url>/health"
```

Los secretos de ambos ambientes deben usar nombres iguales pero valores
propios de cada ambiente.

## 4. Contrato del adaptador de despliegue

Cada ambiente debe exponer un endpoint HTTPS que:

- acepte `POST` con header `Authorization: Bearer <DEPLOY_WEBHOOK_TOKEN>`;
- reciba `{"image": "ghcr.io/<owner>/<repo>@sha256:..."}`;
- despliegue exactamente la referencia recibida, sin reconstruirla;
- responda `{"image_digest": "sha256:..."}` con el digest realmente
  desplegado.

Para ensayar el contrato sin infraestructura existe
`scripts/mock_adapter.py`. El workflow requiere HTTPS, así que para
conectarlo al repositorio hace falta un túnel (por ejemplo `ngrok http 8090`
o `cloudflared tunnel`) que exponga el mock con un certificado válido.

## 5. Paquete GHCR

El workflow publica en `ghcr.io/<owner>/<repo>` usando el `GITHUB_TOKEN`
integrado; no requiere credenciales adicionales. Verificar:

- El bloque `permissions` del workflow ya solicita `packages: write`.
- La visibilidad del paquete (público o privado). Si es privado, el entorno
  que ejecuta la carga de trabajo en la nube necesita credenciales con
  acceso de lectura al paquete; esas credenciales nunca se guardan en el
  repositorio.

## 6. Verificación del flujo

1. Disparar el workflow manualmente: **Actions → Construir y promover imagen
   → Run workflow** (o `gh workflow run deploy.yml`).
2. Con `DEPLOY_ADAPTER_READY` sin definir: `build-and-scan` termina en verde
   (imagen publicada con el SHA del commit y Trivy sin hallazgos HIGH o
   CRITICAL); los jobs de despliegue aparecen omitidos.
3. Con la variable en `true` y el mock adapter expuesto por HTTPS: los
   despliegues en `testing` pasan, `production` queda esperando la
   aprobación y `resumen-promocion` imprime el mismo digest en ambos
   ambientes.

La captura de los tres estados (omisión, espera de aprobación y resumen con
digests idénticos) sirve como evidencia del recorrido
pruebas → validación → aprobación → producción.
