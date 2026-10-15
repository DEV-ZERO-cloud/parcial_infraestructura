# Diseño y pruebas de workflows CI/CD

## Alcance inicial

El pipeline implementa este recorrido: commit en `main` → build único de la imagen → publicación en GHCR con tag del SHA → análisis Trivy por digest → despliegue en `testing` → prueba HTTP → aprobación del Environment `production` → despliegue y prueba en producción → resumen de promoción que compara los digests.

El build pasa `GIT_COMMIT=${{ github.sha }}` como build-arg, así que `/health` responde con el commit exacto que produjo la imagen. El digest producido se conserva como salida del job y se envía sin reconstruir la imagen a ambos ambientes. Cada job de despliegue expone el digest confirmado por su adaptador (`outputs.confirmed_digest`) y el job final `resumen-promocion` compara el digest publicado con el confirmado en cada ambiente, fallando si difieren.

Los jobs de despliegue (`deploy-testing`, `deploy-production` y `resumen-promocion`) solo se ejecutan cuando la variable de repositorio `DEPLOY_ADAPTER_READY` vale `true`. Mientras no exista infraestructura, el run queda en verde con build, Trivy y publicación, y los despliegues aparecen omitidos. El workflow de CI ejecuta `terraform fmt`, `terraform validate` y Checkov al cambiar `infraestructura/`; mientras los `.tf` estén vacíos, informa que la validación de Terraform queda pendiente.

## Contrato pendiente de integrar

La nube, el servicio de ejecución y el proveedor Terraform aún no están definidos en el repositorio. Para evitar asumir un comando específico de AWS o Azure, el workflow usa un adaptador HTTP de despliegue que deberá implementar el equipo o sustituirse por la acción/comando nativo elegido.

El adaptador debe aceptar `POST` sobre HTTPS con autenticación bearer y un cuerpo como:

```json
{"image":"ghcr.io/organizacion/repositorio@sha256:..."}
```

Debe desplegar exactamente la referencia recibida y responder JSON con el digest realmente desplegado:

```json
{"image_digest":"sha256:..."}
```

El proceso que ejecuta la carga de trabajo debe poder descargar la imagen de GHCR. Si el paquete es privado, se debe conceder acceso de lectura al entorno de ejecución; las credenciales no deben incluirse en la URL, en el payload ni en los logs. Para ensayar este contrato sin infraestructura existe `scripts/mock_adapter.py` y la guía completa está en [configuracion_github.md](configuracion_github.md).

## Validación local sin GitHub

`scripts/validar_pipeline_local.sh` replica el pipeline en la máquina local: construye la imagen con el commit actual, la ejecuta, comprueba `/health` (estado y commit) y, si Trivy está instalado, analiza la imagen con el mismo umbral del workflow (HIGH/CRITICAL, `--exit-code 1`).

```bash
bash scripts/validar_pipeline_local.sh
```

## Configuración de GitHub

La guía completa, paso a paso y con comandos `gh`, está en
[configuracion_github.md](configuracion_github.md). Resumen:

- Crear los Environments `testing` y `production` en **Settings →
  Environments**. En `production`, activar required reviewers y limitar los
  branches de despliegue a `main`. La aprobación se configura en GitHub, no
  mediante una confirmación simulada en el YAML.
- Configurar en cada Environment estos valores:

| Tipo | Nombre | Uso |
| --- | --- | --- |
| Secret | `DEPLOY_WEBHOOK_URL` | URL HTTPS del adaptador del ambiente |
| Secret | `DEPLOY_WEBHOOK_TOKEN` | Token bearer del adaptador |
| Variable | `HEALTH_URL` | URL HTTP(S) pública de `/health` |

- Definir la variable de repositorio `DEPLOY_ADAPTER_READY=true` cuando la
  infraestructura y el adaptador estén listos; sin ella, los jobs de
  despliegue quedan omitidos.

El workflow de build publica en `ghcr.io/<propietario>/<repositorio>`. Verificar que Actions tenga permiso para publicar paquetes y que la configuración de visibilidad/acceso del paquete permita al adaptador descargarlo. No guardar credenciales cloud ni tokens en el repositorio.

## Pruebas por workflow

### `Validar infraestructura` (`ci.yml`)

1. Abrir un PR que cambie un archivo en `infraestructura/` y confirmar que inicia el workflow.
2. Confirmar que `terraform fmt -check -recursive` pasa con los archivos formateados; introducir temporalmente formato incorrecto en una rama de prueba y confirmar que falla.
3. Con Terraform implementado, confirmar que `terraform init -backend=false` y `terraform validate` pasan. Introducir temporalmente una referencia o tipo inválido y confirmar que la validación falla.
4. Confirmar que Checkov analiza `infraestructura/` y que un hallazgo que incumpla la política configurada bloquea el job.
5. Mientras los `.tf` sigan vacíos, confirmar que el job termina dejando explícito que `validate` y Checkov no se ejecutaron por falta de configuración.

### `Construir y promover imagen` (`deploy.yml`)

1. Enviar un commit de prueba a `main` y confirmar que solo se ejecuta un build, se publica el tag `<SHA completo>` en GHCR y Trivy analiza la imagen referenciada por `@sha256:...`.
2. Confirmar que `/health` de la imagen publicada responde el SHA del commit (verificable con `docker buildx imagetools inspect` y ejecutando la imagen, o con la respuesta de la prueba HTTP del ambiente).
3. Con `DEPLOY_ADAPTER_READY` sin definir, confirmar que `deploy-testing`, `deploy-production` y `resumen-promocion` quedan omitidos y el run termina en verde.
4. Confirmar que vulnerabilidades `HIGH` o `CRITICAL` sin corregir hacen fallar Trivy y bloquean ambos despliegues. Revisar que la imagen no se despliegue cuando falla el escaneo.
5. Con el adaptador de prueba listo (mock expuesto por HTTPS con túnel), verificar que `testing` recibe `image: ghcr.io/...@sha256:...`, autentica la petición y responde el mismo `image_digest`.
6. Comprobar que una respuesta HTTP no exitosa, un token ausente/incorrecto, una respuesta sin `image_digest` o un digest distinto hacen fallar `deploy-testing` y no habilitan producción.
7. Confirmar que `HEALTH_URL` responde HTTP exitoso. Probar una URL incorrecta o servicio no disponible y verificar que los reintentos terminan en fallo.
8. Confirmar que el job `production` queda esperando la aprobación de GitHub y que no se invoca el adaptador antes de aprobar.
9. Aprobar el despliegue y comprobar en los logs del adaptador/servicio que el digest recibido en producción es idéntico al de `testing`; verificar además la salud HTTP de producción.
10. Confirmar que `resumen-promocion` imprime el tag, el digest publicado y el confirmado en cada ambiente, y que termina en verde solo si todos coinciden.
11. Comparar el digest publicado en GHCR, el solicitado en ambos payloads y el reportado por cada adaptador. Los tres deben ser idénticos; el historial del run debe mostrar un único build y ningún build entre los ambientes.
12. Confirmar que los logs no imprimen el token bearer ni credenciales del registro.

## Evidencias para la entrega

- URL del run de GitHub Actions con build, digest, resultado Trivy y despliegues.
- Captura o logs de la espera y aprobación de `production`.
- Log del job `resumen-promocion` con el digest publicado y los confirmados en cada ambiente.
- Digest de la imagen publicado y digest confirmado por cada ambiente.
- Respuesta HTTP exitosa de `/health` en `testing` y producción.
- Resultado del workflow de Terraform/Checkov después de implementar los archivos `.tf`.

## Estado de las tareas de Persona 3

| Tarea del plan | Estado |
| --- | --- |
| Workflows con permisos mínimos | Listo (`contents`/`packages` restringidos por job) |
| Construir una vez y etiquetar con el SHA del commit | Listo (build-arg `GIT_COMMIT` incluido) |
| Ejecutar Trivy antes del despliegue | Listo (umbral HIGH/CRITICAL, `exit-code 1`) |
| Publicar la imagen en el registro | Listo en GHCR; migrar a ECR/ACR cuando el equipo defina la nube |
| Desplegar en pruebas con la imagen ya construida | Estructura lista; requiere adaptador/infraestructura real |
| Prueba HTTP automática contra pruebas | Estructura lista; requiere `HEALTH_URL` del ambiente |
| Environment `production` con aprobación requerida | Pendiente de configurar en GitHub (ver `configuracion_github.md`) |
| Promover en producción la misma imagen por digest | Listo (misma referencia `image_ref`, sin rebuild) |
| Registrar tag y digest en los logs de cada ambiente | Listo (logs por job + job `resumen-promocion`) |
| Terraform activa comprobaciones de CI; sin secretos en logs | Listo (`ci.yml` por rutas; secretos solo vía `secrets`/env) |

## Limitaciones conocidas

- El webhook es una interfaz temporal de integración: debe implementarse o reemplazarse por el despliegue nativo cuando Persona 1 defina nube y recursos.
- GHCR es el registro inicial escogido para que el workflow sea independiente de AWS/Azure. Si el equipo requiere ECR o ACR, se debe cambiar el paso de login/publicación y conservar el flujo por digest.
- La ejecución real de los despliegues queda condicionada a que existan infraestructura, aplicación con `/health`, adaptadores, variables y secretos de los Environments, y a que `DEPLOY_ADAPTER_READY` valga `true`.
- El job `resumen-promocion` solo ejecuta cuando los despliegues están activados; con los despliegues omitidos no produce evidencia.