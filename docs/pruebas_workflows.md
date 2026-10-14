# Diseño y pruebas de workflows CI/CD

## Alcance inicial

El pipeline implementa este recorrido: commit en `main` → build único de la imagen → publicación en GHCR con tag del SHA → análisis Trivy por digest → despliegue en `testing` → prueba HTTP → aprobación del Environment `production` → despliegue y prueba en producción.

El digest producido por el build se conserva como salida del job y se envía sin reconstruir la imagen a ambos ambientes. La verificación del endpoint de despliegue compara el digest que devuelve con el solicitado. El workflow de CI ejecuta `terraform fmt`, `terraform validate` y Checkov al cambiar `infraestructura/`; mientras los `.tf` estén vacíos, informa que la validación de Terraform queda pendiente.

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

El proceso que ejecuta la carga de trabajo debe poder descargar la imagen de GHCR. Si el paquete es privado, se debe conceder acceso de lectura al entorno de ejecución; las credenciales no deben incluirse en la URL, en el payload ni en los logs.

## Configuración de GitHub

Crear los Environments `testing` y `production` en **Settings → Environments**. En `production`, activar required reviewers y limitar los branches de despliegue a `main`. La aprobación se configura en GitHub, no mediante una confirmación simulada en el YAML.

Configurar en cada Environment estos valores:

| Tipo | Nombre | Uso |
| --- | --- | --- |
| Secret | `DEPLOY_WEBHOOK_URL` | URL HTTPS del adaptador del ambiente |
| Secret | `DEPLOY_WEBHOOK_TOKEN` | Token bearer del adaptador |
| Variable | `HEALTH_URL` | URL HTTP(S) pública de `/health` |

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
2. Confirmar que vulnerabilidades `HIGH` o `CRITICAL` sin corregir hacen fallar Trivy y bloquean ambos despliegues. Revisar que la imagen no se despliegue cuando falla el escaneo.
3. Con el adaptador de prueba listo, verificar que `testing` recibe `image: ghcr.io/...@sha256:...`, autentica la petición y responde el mismo `image_digest`.
4. Comprobar que una respuesta HTTP no exitosa, un token ausente/incorrecto, una respuesta sin `image_digest` o un digest distinto hacen fallar `deploy-testing` y no habilitan producción.
5. Confirmar que `HEALTH_URL` responde HTTP exitoso. Probar una URL incorrecta o servicio no disponible y verificar que los reintentos terminan en fallo.
6. Confirmar que el job `production` queda esperando la aprobación de GitHub y que no se invoca el adaptador antes de aprobar.
7. Aprobar el despliegue y comprobar en los logs del adaptador/servicio que el digest recibido en producción es idéntico al de `testing`; verificar además la salud HTTP de producción.
8. Comparar el digest publicado en GHCR, el solicitado en ambos payloads y el reportado por cada adaptador. Los tres deben ser idénticos; el historial del run debe mostrar un único build y ningún build entre los ambientes.
9. Confirmar que los logs no imprimen el token bearer ni credenciales del registro.

## Evidencias para la entrega

- URL del run de GitHub Actions con build, digest, resultado Trivy y despliegues.
- Captura o logs de la espera y aprobación de `production`.
- Digest de la imagen publicado y digest confirmado por cada ambiente.
- Respuesta HTTP exitosa de `/health` en `testing` y producción.
- Resultado del workflow de Terraform/Checkov después de implementar los archivos `.tf`.

## Limitaciones conocidas

- El webhook es una interfaz temporal de integración: debe implementarse o reemplazarse por el despliegue nativo cuando Persona 1 defina nube y recursos.
- GHCR es el registro inicial escogido para que el workflow sea independiente de AWS/Azure. Si el equipo requiere ECR o ACR, se debe cambiar el paso de login/publicación y conservar el flujo por digest.
- La ejecución real queda condicionada a que existan infraestructura, aplicación con `/health`, adaptadores, variables y secretos de los Environments.