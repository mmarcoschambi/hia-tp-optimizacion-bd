# Parte IX: Memoria, Servidor y Rendimiento

## Punto 43. Configuración del Servidor (MySQL / InnoDB)
El archivo principal de configuración en MySQL es `my.cnf` (o `my.ini`). Para garantizar un rendimiento óptimo ante cargas masivas de información, se identificaron y ajustaron los siguientes parámetros clave:

* **`innodb_buffer_pool_size`**: Asigna la cantidad de memoria RAM dedicada a mantener en caché los datos e índices de las tablas InnoDB. Se recomienda configurarlo entre el 60% y 80% de la RAM del servidor.
* **`max_connections`**: Controla el límite de conexiones concurrentes para evitar la saturación de memoria por hilos activos.
* **`sort_buffer_size` y `join_buffer_size`**: Memoria asignada por conexión para operaciones de ordenamiento (`ORDER BY`) y uniones sin índices adecuados.
* **`tmp_table_size` y `max_heap_table_size`**: Limitan el tamaño de las tablas temporales en RAM. Si una consulta supera este umbral, la tabla se escribe en disco degradando la velocidad.

---

## Punto 44. InnoDB Buffer Pool
El Buffer Pool administra la memoria RAM dividiéndola en páginas (bloques de 16 KB). 
* **Cache Hit vs. Cache Miss**: Cuando se ejecuta una consulta sobre la tabla de reservas, el motor busca primero la página en memoria RAM (*Cache Hit*). Si no está disponible (*Cache Miss* o *Cold Cache*), realiza una operación física de I/O para cargarla desde el almacenamiento.
* **Impacto**: Para una tabla masiva de 6 millones de registros, disponer de un Buffer Pool bien dimensionado permite alojar los índices en RAM, reduciendo los tiempos de respuesta de segundos a milisegundos.

---

## Punto 45. Análisis de Cuellos de Botella (CPU, Disco y Red)
* **Limitado por Disco (I/O Bound)**: Consultas que realizan escaneos completos (*Full Table Scan*) sobre millones de filas al carecer de índices o por falta de SARGabilidad.
* **Limitado por CPU (CPU Bound)**: Consultas que procesan cálculos complejos en memoria, como agregaciones (`SUM`, `COUNT`), funciones de fechas (`DATEDIFF`) y agrupamientos masivos (`GROUP BY`).
* **Limitado por Red (Network Bound)**: Sentencias sin la cláusula `LIMIT` adecuada o que proyectan columnas innecesarias (`SELECT *`), saturando el ancho de banda en la transferencia de datos.

---

## Punto 46. Connection Pool
* **Conexiones Directas**: Cada apertura de conexión implica un handshake TCP, autenticación y asignación de estructuras de memoria en MySQL, generando un costo elevado bajo alta concurrencia.
* **Pool de Conexiones**: Mantiene un conjunto de conexiones preestablecidas y reutilizables. Esto elimina la latencia de creación/cierre y evita el agotamiento de recursos en el servidor.

---

## Punto 47. Slow Query Log y Diagnóstico
Se configuró el registro de consultas lentas en MySQL para identificar cuellos de botella en producción:
```sql
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 2;
SET GLOBAL log_queries_not_using_indexes = 1;
`
---

## Punto 48. Tareas de Mantenimiento Preventivo
A medida que la tabla `reserva` incrementa su volumen hasta alcanzar millones de registros, se requiere ejecutar tareas de mantenimiento preventivo para mantener la eficiencia en el acceso a datos:

1. **`ANALYZE TABLE reserva;`**:
   Actualiza las estadísticas de cardinalidad y distribución de los datos en los índices. Esto le permite al optimizador de consultas de MySQL tomar mejores decisiones y elegir el plan de ejecución más eficiente.

2. **`OPTIMIZE TABLE reserva;`**:
   Reconstruye físicamente la tabla y desfragmenta los árboles B-Tree de los índices. Tras operaciones masivas de inserción (`INSERT`), modificación (`UPDATE`) o borrado (`DELETE`), recupera el espacio no utilizado en disco y mejora la velocidad de lectura.

---

# Parte X: Escalabilidad, Particionamiento y Estructuras Avanzadas

## Punto 49. Escalabilidad Vertical vs. Horizontal
Al enfrentar un crecimiento masivo de datos e interacciones en la base de datos relacional, se analizan dos estrategias principales:

* **Escalabilidad Vertical (Scale-Up)**:
  Consiste en potenciar el servidor existente agregando mejores componentes físicos (mayor memoria RAM, procesadores con más núcleos o discos de almacenamiento SSD NVMe de alta velocidad).
  * *Ventajas*: No requiere modificar la estructura de las consultas SQL ni la arquitectura de la aplicación.
  * *Desventajas*: Posee un límite físico y económico claro (el hardware tope de gama es sumamente costoso).

* **Escalabilidad Horizontal (Scale-Out)**:
  Consiste en distribuir la carga de la base de datos entre múltiples servidores (nodos) trabajando en conjunto, utilizando réplicas de lectura (*Read Replicas*) o división de datos (*Sharding*).
  * *Ventajas*: Ofrece un potencial de crecimiento prácticamente ilimitado.
  * *Desventajas*: Incrementa notablemente la complejidad técnica para mantener la consistencia transaccional (propiedades ACID) entre nodos distribuidos.

---

## Punto 50. Particionamiento de Tablas
Para optimizar el acceso a nivel físico sobre la tabla masiva `reserva` (que cuenta con un volumen superior a los 6 millones de registros), se implementó una estrategia de **particionamiento por rango (`RANGE`)** basada en el año de la columna `fecha_inicio`.

Esta división física segmenta los datos en particiones independientes por año de gestión (`p_historico`, `p_2023`, `p_2024`, `p_2025` y `p_futuro`), manteniendo la tabla como una entidad lógica única para las consultas de la aplicación.

---

## Punto 51. Partition Pruning (Poda de Particiones)
El ***Partition Pruning*** es una técnica de optimización donde el motor de MySQL analiza las condiciones de filtrado en la cláusula `WHERE` y descarta automáticamente la lectura de las particiones físicas que no contienen datos relevantes para la consulta.

* **Demostración:** Al consultar reservas dentro del rango de junio a diciembre de 2023, la ejecución de `EXPLAIN PARTITIONS` confirma que el optimizador escanea únicamente la partición `p_2023`. Se omiten por completo las demás particiones del disco, reduciendo las operaciones de entrada/salida (I/O) en hasta un 80%.

---

## Punto 52. Vistas y Vistas Materializadas
Dado que MySQL / MariaDB no soportan de forma nativa la instrucción `CREATE MATERIALIZED VIEW`, se diseñó una **Tabla Resumen (Summary Table)** precalculada (`vista_mat_resumen_mensual_hotel`) para acelerar las consultas analíticas de alta carga.

* **Estrategia y Refresco:** Un proceso batch consolidado procesa los `JOIN` pesados entre las tablas `reserva`, `habitacion`, `hotel` y `tipo_habitacion`, guardando los totales de ocupación e ingresos mensuales por hotel en la tabla resumen.
* **Ventaja de Rendimiento:** Las consultas de reportes ejecutadas sobre la tabla de resumen responden de forma instantánea (en milisegundos), evitando recorrer repetidamente los 6 millones de registros históricos de la tabla principal.

