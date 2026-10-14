# Plan de trabajo --- Estrella de Israel

## Segundo parcial: Infraestructura para TI

**Taller asignado:** 8. Promoción de una misma imagen entre ambientes\
**Fecha límite:** miércoles 14 de octubre de 2026, 11:59 p. m. (hora de
Colombia)\
**Equipo:** Estrella de Israel\
**Objetivo:** construir una imagen Docker una sola vez, analizarla,
publicarla en un registro de AWS o Azure, desplegarla en pruebas,
verificarla mediante una prueba HTTP, solicitar aprobación para
producción y promover exactamente la misma imagen ---identificada por su
digest--- al ambiente productivo.

> **Regla de trabajo:** priorizar una solución mínima, reproducible y
> demostrable. La aplicación puede ser sencilla; la evaluación se
> concentra en Terraform, CI/CD, seguridad, promoción de artefactos,
> evidencias y documentación.

## 1. Entregables obligatorios

-   [ ] Repositorio público o accesible para evaluación en GitHub.
-   [ ] Aplicación mínima contenerizada y `Dockerfile`.
-   [ ] Infraestructura de los ambientes de pruebas y producción
    definida con Terraform.
-   [ ] Registro de imágenes de AWS o Azure.
-   [ ] Workflow de GitHub Actions que construya la imagen una sola vez
    y la etiquete con el identificador del commit.
-   [ ] Análisis de la imagen con Trivy antes de desplegarla.
-   [ ] Despliegue de la imagen en el ambiente de pruebas.
-   [ ] Prueba HTTP automática del ambiente de pruebas.
-   [ ] Aprobación manual antes del despliegue en producción, mediante
    GitHub Environments.
-   [ ] Promoción a producción de la misma imagen, sin reconstruirla.
-   [ ] Evidencia de que pruebas y producción usan el mismo digest.
-   [ ] Ejecución de Checkov sobre Terraform; además, `terraform fmt` y
    `terraform validate`.
-   [ ] README técnico con arquitectura, prerrequisitos, variables,
    configuración de secretos, instrucciones, URL o procedimiento de
    prueba, evidencias, limitaciones y destrucción de recursos.
-   [ ] Diagrama de arquitectura.
-   [ ] Evidencias de workflows, análisis de seguridad, prueba HTTP,
    aprobación y despliegues.
-   [ ] Registro breve de decisiones, limitaciones y mejoras futuras.

## 2. Distribución del trabajo entre cuatro personas

Los nombres personales se pueden agregar al asignar las tareas. Cada
responsable debe dejar sus cambios en una rama o carpeta acordada y
comunicar cómo probarlos. La integración final corresponde a todo el
equipo.

### Persona 1 --- Infraestructura como código y nube

**Responsabilidad principal:** Terraform y configuración de los
ambientes.

-   [ ] Elegir con el equipo AWS o Azure y confirmar que todos tienen
    acceso.
-   [ ] Definir la arquitectura mínima de pruebas y producción.
-   [ ] Crear los recursos necesarios y el registro de contenedores con
    Terraform.
-   [ ] Parametrizar los ambientes para evitar duplicación innecesaria.
-   [ ] Añadir etiquetas/tags que identifiquen equipo, proyecto y
    ambiente.
-   [ ] Establecer límites de recursos de bajo costo y revisar los
    costos potenciales.
-   [ ] Ejecutar `terraform fmt`, `terraform validate` y Checkov.
-   [ ] Entregar instrucciones de inicialización, despliegue y
    destrucción.
-   [ ] Proporcionar al responsable de CI/CD los nombres de recursos,
    salidas y variables necesarias.

**Entregable individual:** código Terraform funcional, validaciones y
evidencia de infraestructura aplicada.

### Persona 2 --- Aplicación, Docker y registro de imágenes

**Responsabilidad principal:** aplicación mínima y artefacto
reproducible.

-   [ ] Crear o adaptar una aplicación HTTP sencilla que responda en una
    ruta de salud, por ejemplo `/health`.
-   [ ] Hacer que la aplicación muestre una versión o identificador del
    commit para facilitar la comprobación.
-   [ ] Crear un `Dockerfile` mínimo, reproducible y con buenas
    prácticas de seguridad.
-   [ ] Evitar incluir credenciales, tokens o archivos `.env` con
    secretos en la imagen.
-   [ ] Probar localmente la construcción y ejecución del contenedor.
-   [ ] Acordar con Persona 1 el registro de imágenes y con Persona 3 el
    nombre de imagen y las etiquetas.
-   [ ] Comprobar que la imagen publicada queda identificada por el
    commit y que se puede recuperar su digest.
-   [ ] Entregar instrucciones para ejecutar la aplicación y probar
    `/health`.

**Entregable individual:** código de aplicación, `Dockerfile`, prueba
local y datos del artefacto publicado.

### Persona 3 --- CI/CD y promoción entre ambientes

**Responsabilidad principal:** automatización en GitHub Actions.

-   [ ] Crear o configurar los workflows y sus permisos mínimos.
-   [ ] Construir la imagen una sola vez por commit y etiquetarla con el
    SHA del commit.
-   [ ] Ejecutar Trivy antes de permitir el despliegue.
-   [ ] Publicar la imagen en el registro de AWS o Azure.
-   [ ] Desplegar en pruebas usando la imagen ya construida.
-   [ ] Ejecutar una prueba HTTP automática contra el ambiente de
    pruebas.
-   [ ] Configurar un ambiente de GitHub llamado `production` con
    aprobación requerida, si está disponible en la configuración del
    repositorio.
-   [ ] Después de la aprobación, promover/desplegar en producción la
    misma imagen por digest; no volver a construirla.
-   [ ] Registrar en los logs el tag y digest usados en cada ambiente.
-   [ ] Validar que cambios en Terraform activen las comprobaciones de
    infraestructura correspondientes y que no se expongan secretos en
    logs.

**Entregable individual:** workflows funcionales y evidencia del
recorrido pruebas → validación → aprobación → producción.

### Persona 4 --- Seguridad, pruebas, documentación e integración

**Responsabilidad principal:** comprobar los criterios de evaluación y
consolidar evidencias.

-   [ ] Crear el esqueleto del README y una lista de verificación común.
-   [ ] Configurar o verificar GitHub Secrets/OIDC según la nube
    seleccionada; nunca guardar credenciales en el repositorio.
-   [ ] Revisar que el repositorio no contenga claves, tokens ni
    archivos sensibles.
-   [ ] Ejecutar o coordinar Checkov y Trivy; registrar los resultados y
    corregir hallazgos relevantes.
-   [ ] Preparar la prueba HTTP de salud y verificar la respuesta del
    ambiente de pruebas.
-   [ ] Recopilar capturas o logs de la construcción, publicación,
    despliegue, aprobación y resultado final.
-   [ ] Comparar el digest desplegado en pruebas con el de producción.
-   [ ] Crear el diagrama de arquitectura y documentar variables,
    decisiones, limitaciones y mejoras.
-   [ ] Revisar que los enlaces del repositorio, aplicación y evidencias
    funcionen.
-   [ ] Coordinar una demostración final de extremo a extremo.

**Entregable individual:** README, diagrama, evidencias, revisión de
seguridad y lista final de aceptación.

## 3. Cronograma de hoy --- 14 de octubre

  --------------------------------------------------------------------------
  Hora (Colombia)   Actividad            Responsable(s)    Resultado
                                                           esperado
  ----------------- -------------------- ----------------- -----------------
  9:35--9:50 a. m.  Reunión de inicio:   Todos             Decisiones
                    elegir nube,                           anotadas y tareas
                    confirmar accesos,                     asignadas
                    definir aplicación y                   
                    arquitectura mínima                    

  9:50--11:30 a. m. Trabajo en paralelo: Personas 1--4     Primeros archivos
                    Terraform,                             y estructura del
                    aplicación/Docker,                     repositorio
                    diseño de workflows                    
                    y README/lista de                      
                    evidencias                             

  11:30 a.          Integración inicial: Personas 1--3;    Componentes
  m.--12:00 m.      acordar nombres de   Persona 4         compatibles entre
                    recursos, variables, registra          sí
                    imagen y rutas HTTP                    

  12:00--1:00 p. m. Aplicar              Personas 1--3     Recursos e imagen
                    infraestructura                        local listos
                    mínima y probar                        
                    contenedor; resolver                   
                    bloqueos de permisos                   
                    o nube                                 

  1:00--2:00 p. m.  Pausa y revisión del Todos             Lista de bloqueos
                    estado                                 actualizada

  2:00--3:30 p. m.  Implementar          Personas 2--3;    Imagen publicada
                    construcción única,  Persona 1 apoya   y pruebas
                    Trivy, publicación y                   desplegadas
                    despliegue en                          
                    pruebas                                

  3:30--4:15 p. m.  Ejecutar prueba      Personas 1, 3 y 4 Validaciones
                    HTTP, Checkov y                        registradas y
                    validaciones de                        ambiente de
                    Terraform; corregir                    pruebas sano
                    errores críticos                       

  4:15--5:15 p. m.  Configurar           Persona 3;        Producción
                    aprobación de        Persona 1 apoya;  desplegada con el
                    producción y         Persona 4         mismo digest
                    desplegar la misma   verifica          
                    imagen por digest                      

  5:15--6:15 p. m.  Pruebas de           Todos             Criterios
                    aceptación, revisión                   técnicos
                    de seguridad y                         verificados
                    comprobación de                        
                    evidencias                             

  6:15--7:15 p. m.  Completar README,    Persona 4; todos  Documentación
                    diagrama,            aportan           completa
                    decisiones,                            
                    limitaciones y                         
                    procedimiento de                       
                    destrucción                            

  7:15--8:00 p. m.  Ensayo de            Todos             Demostración
                    demostración y                         repetible
                    corrección de fallos                   
                    bloqueantes                            

  8:00--9:00 p. m.  Margen de            Responsables      Entrega estable
                    contingencia para    según el bloqueo  
                    fallos de nube,                        
                    permisos o workflow                    

  9:00--10:00 p. m. Revisión final del   Todos             Lista de
                    repositorio y de                       aceptación
                    todos los                              completa
                    entregables                            

  10:00--11:00      Congelar cambios     Personas 3--4;    Evidencias
  p. m.             funcionales; tomar   Persona 1 revisa  finales y
                    evidencias           infraestructura   documentación
                    definitivas y probar                   verificable
                    instrucciones del                      
                    README                                 

  11:00--11:30      Preparar enlaces,    Todos             Presentación
  p. m.             orden de exposición                    lista
                    y explicación de                       
                    decisiones                             

  11:30--11:59      Verificación final y Todos             Enlaces
  p. m.             entrega                                entregados antes
                                                           del límite
  --------------------------------------------------------------------------

**Si se acumula retraso:** mantener como prioridad el flujo mínimo
completo: Terraform aplicado → imagen construida una sola vez → Trivy →
registro → pruebas → prueba HTTP → aprobación → producción con el mismo
digest. Evitar agregar funcionalidades no exigidas.

## 4. Procedimiento técnico de extremo a extremo

1.  **Acordar y preparar:** seleccionar AWS o Azure, confirmar permisos,
    crear el repositorio y definir nombres, variables y responsables.
2.  **Crear la infraestructura:** desarrollar Terraform para los dos
    ambientes y el registro; ejecutar formato, validación y Checkov
    antes de aplicar cambios.
3.  **Preparar la aplicación:** crear la ruta de salud, añadir un
    identificador de versión y construir el contenedor localmente.
4.  **Construir una única vez:** desde GitHub Actions, construir la
    imagen y etiquetarla con el SHA del commit. No reconstruirla para
    producción.
5.  **Analizar y publicar:** ejecutar Trivy, corregir o justificar los
    hallazgos según su severidad y publicar la imagen en el registro.
6.  **Desplegar en pruebas:** desplegar el artefacto publicado, no una
    compilación distinta; registrar su digest.
7.  **Verificar:** ejecutar la prueba HTTP automatizada y confirmar que
    la aplicación responde correctamente.
8.  **Solicitar aprobación:** detener el workflow antes de producción y
    requerir aprobación mediante GitHub Environments.
9.  **Promover a producción:** después de aprobar, desplegar el mismo
    artefacto por digest. No reconstruir ni sustituir la imagen.
10. **Comprobar identidad:** verificar y guardar evidencia de que el
    digest de pruebas coincide con el digest de producción.
11. **Documentar y cerrar:** completar README, diagrama, resultados de
    seguridad, URLs, limitaciones y procedimiento para destruir
    recursos.

## 5. Criterios de aceptación final

-   [ ] El repositorio de GitHub contiene todo el código necesario.
-   [ ] Terraform crea los recursos de ambos ambientes y pasa `fmt` y
    `validate`.
-   [ ] Checkov se ejecuta sobre Terraform y sus resultados quedan
    documentados.
-   [ ] GitHub Actions construye la imagen una sola vez por commit.
-   [ ] Trivy analiza la imagen antes del despliegue.
-   [ ] La imagen se publica en un registro de AWS o Azure.
-   [ ] La aplicación responde correctamente a la prueba HTTP en
    pruebas.
-   [ ] Producción requiere aprobación antes del despliegue.
-   [ ] No se reconstruye la imagen para producción.
-   [ ] El digest de pruebas es idéntico al de producción y existe
    evidencia verificable.
-   [ ] No hay credenciales almacenadas en el repositorio.
-   [ ] Los recursos tienen etiquetas de equipo/proyecto/ambiente y
    límites razonables de costo.
-   [ ] README, diagrama, URLs, evidencias y procedimiento de
    destrucción están completos.
-   [ ] El equipo puede repetir la demostración y explicar las
    decisiones técnicas.

## 6. Estructura sugerida del repositorio

``` text
estrella-de-israel/
├── app/
│   └── ...                 # Código de la aplicación mínima
├── Dockerfile
├── infra/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── ...                 # Archivos/módulos Terraform
├── .github/
│   └── workflows/
│       ├── ci.yml
│       └── deploy.yml      # Puede ser uno o varios workflows
├── docs/
│   ├── arquitectura.md
│   └── evidencias/
└── README.md
```

La estructura puede ajustarse a la nube elegida. No subir archivos de
estado de Terraform, claves privadas, credenciales ni archivos locales
con secretos al repositorio.

## 7. Registro de decisiones y bloqueos

  -------------------------------------------------------------------------
  Tema              Decisión / estado   Responsable       Evidencia o
                                                          acción pendiente
  ----------------- ------------------- ----------------- -----------------
  Nube elegida      Por definir al      Todos             Confirmar acceso
  (AWS/Azure)       inicio                                y presupuesto

  Registro de       Por definir         Personas 1 y 2    Nombre y URI del
  imágenes                                                registro

  Servicio de       Por definir según   Persona 1         Recursos de
  ejecución         la nube                               pruebas y
                                                          producción

  Autenticación de  OIDC preferido;     Personas 1 y 3    Confirmar
  GitHub Actions    Secrets si es                         permisos mínimos
                    necesario                             

  Ruta de salud     `/health`           Personas 2 y 3    Confirmar
  HTTP              (propuesta)                           respuesta
                                                          esperada

  Política de Trivy Definir umbral y    Personas 3 y 4    Guardar reporte
                    documentar                            
                    excepciones                           

  Digest de pruebas Pendiente de        Personas 3 y 4    Registrar ambos y
  y producción      ejecución                             comparar

  Destrucción de    Pendiente de        Personas 1 y 4    Incluir comando y
  recursos          documentar/probar                     precauciones
  -------------------------------------------------------------------------

## 8. Orden recomendado para la demostración

1.  Mostrar el repositorio y explicar brevemente la arquitectura.
2.  Mostrar Terraform y los resultados de `terraform fmt`,
    `terraform validate` y Checkov.
3.  Mostrar el workflow: construcción única, etiqueta del commit,
    análisis Trivy y publicación.
4.  Mostrar el despliegue de pruebas y la prueba HTTP exitosa.
5.  Mostrar la aprobación requerida antes de producción.
6.  Mostrar el despliegue productivo y comparar los digest de ambos
    ambientes.
7.  Mostrar el README, las evidencias y el procedimiento para destruir
    la infraestructura.

**Fuente de requisitos:** *Enunciados segundo parcial ---
Infraestructura para TI*, página 11 (Taller 8), páginas 2--3
(condiciones obligatorias, entregables comunes y rúbrica general).
