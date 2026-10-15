# Diseño y pruebas de workflows CI/CD

## Recorrido implementado y verificado

```
commit en main → build ÚNICO (tag = SHA) → push a ECR → digest confirmado
  → Trivy por digest (bloquea HIGH/CRITICAL)
  → deploy-testing (Environment test): registra revisión de tarea con repo@sha256:<digest>,
    update-service, espera de estabilidad, verificación de digest y prueba HTTP /health
  → deploy-production (Environment production, APROBACIÓN MANUAL REQUERIDA)
  → misma referencia por digest, sin rebuild → prueba HTTP /health
  → resumen-promocion: compara digest publicado vs confirmado en cada ambiente
```

El build pasa `GIT_COMMIT=${{ github.sha }}` como build-arg, así que `/health`
responde con el commit exacto que produjo la imagen. El job `build-and-scan`
expone `image_ref` (referencia inmutable `repo@sha256:<digest>`) y `digest`;
ambos jobs de despliegue consumen esas salidas y confirman el digest realmente
desplegado antes de declararse exitosos. `resumen-promocion` falla si algún
digest difiere.

**Ejecución de referencia (todo verde):**
[run 38676879961](https://github.com/DEV-ZERO-cloud/parcial_infraestructura/actions/runs/38676879961)
— commit `94950b4`, 2026-10-15. La cronología completa de jobs y pasos
(incluida la espera de aprobación de producción) está capturada en
`docs/evidencias/run_verde_38676879961.json` y en
`docs/evidencias/deployments_timeline.txt`.

## Validación de infraestructura (`ci.yml`)

Se activa con cambios en `infraestructura/**` y ejecuta `terraform fmt -check`,
`terraform init -backend=false`, `terraform validate` y **Checkov**
(política `.checkov.yaml`). Ha pasado en cada commit que tocó infraestructura;
ver runs de `Validar infraestructura` en
[Actions](https://github.com/DEV-ZERO-cloud/parcial_infraestructura/actions).
Además, las validaciones se ejecutaron localmente y sus salidas están en
`docs/evidencias/` (`terraform_fmt.txt`, `terraform_validate.txt`,
`results_cli.txt` de Checkov).

## Pruebas ejecutadas sobre `deploy.yml`

1. **Build único por commit**: el historial del run muestra un solo build; el
   tag publicado en ECR es el SHA completo del commit.
2. **Digest confirmado contra ECR**: el paso `Confirmar digest en ECR` compara
   el digest del build con el `imageDigest` de `describe-images` y fallaría si
   difirieran.
3. **Trivy como compuerta**: el escaneo usa `--exit-code 1` con severidades
   HIGH/CRITICAL sobre la imagen por digest; un hallazgo haría fallar el run y
   los despliegues no se ejecutarían (`needs: build-and-scan`).
4. **Despliegue en pruebas**: `deploy-testing` registra una nueva revisión de la
   definición de tarea con la imagen por digest, actualiza el servicio, espera a
   `services-stable`, verifica que el digest desplegado es el esperado y ejecuta
   la prueba HTTP contra `APP_URL/health`.
5. **Aprobación manual**: `deploy-production` pertenece al Environment
   `production` con required reviewers; quedó esperando la aprobación entre
   04:05:37Z y 04:09:59Z (ver `deployments_timeline.txt`).
6. **Promoción sin reconstrucción**: el job de producción usa
   `needs.build-and-scan.outputs.image_ref`; no contiene ningún paso de build.
7. **Identidad de la imagen**: `resumen-promocion` comparó los tres digests
   (publicado, testing, producción) y terminó en verde.
8. **Prueba HTTP final en vivo**: ambos ambientes responden 200 con el mismo
   commit `94950b4` (`docs/evidencias/http_final_ambos_ambientes.txt`).
9. **Sin secretos en logs**: la autenticación es OIDC; los logs solo muestran el
   ARN del rol asumido, nunca claves.

## Estado de las tareas de Persona 3

| Tarea del plan | Estado |
| --- | --- |
| Workflows con permisos mínimos | ✅ Listo (`contents: read`, `id-token: write` solo donde se necesita) |
| Construir una vez y etiquetar con el SHA del commit | ✅ Listo (tag = SHA; build-arg `GIT_COMMIT`) |
| Ejecutar Trivy antes del despliegue | ✅ Listo (umbral HIGH/CRITICAL, `exit-code 1`) |
| Publicar la imagen en el registro | ✅ Listo en Amazon ECR (tags inmutables) |
| Desplegar en pruebas con la imagen ya construida | ✅ Listo y verificado en el run verde |
| Prueba HTTP automática contra pruebas | ✅ Listo (curl con reintentos a `APP_URL/health`) |
| Environment `production` con aprobación requerida | ✅ Configurado (required reviewers + branch `main`) |
| Promover en producción la misma imagen por digest | ✅ Listo (misma `image_ref`, sin rebuild) |
| Registrar tag y digest en los logs de cada ambiente | ✅ Listo (logs por job + job `resumen-promocion`) |
| Terraform activa comprobaciones de CI; sin secretos en logs | ✅ Listo (`ci.yml` por rutas; autenticación OIDC) |

## Evidencias para la entrega

- Run verde completo: [run 38676879961](https://github.com/DEV-ZERO-cloud/parcial_infraestructura/actions/runs/38676879961).
- Cronología de deployments con la ventana de aprobación: `docs/evidencias/deployments_timeline.txt`.
- Detalle de jobs/pasos del run: `docs/evidencias/run_verde_38676879961.json`.
- Prueba HTTP en ambos ambientes con el mismo commit: `docs/evidencias/http_final_ambos_ambientes.txt`.
- Valores vigentes de Terraform: `docs/evidencias/Outputs.txt`.
- Validaciones de Terraform y Checkov: `docs/evidencias/terraform_*.txt`, `results_cli.txt`, `results_json.json`.
- Runs de `Validar infraestructura` en verde en el historial de Actions.

## Limitaciones conocidas

- Trivy descarta vulnerabilidades sin parche disponible (`ignore-unfixed`).
- Las URLs de los ALB cambian si la infraestructura se destruye y re-crea; hay
  que actualizar `APP_URL` en los Environments.
- El rol OIDC que asume GitHub Actions fue creado manualmente en AWS (no por
  Terraform); si la cuenta es de laboratorio, puede desaparecer al resetearse.
- El tiempo de espera de estabilidad de ECS está limitado a 12 minutos por job.
