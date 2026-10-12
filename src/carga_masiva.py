import random
from datetime import date, timedelta
import mysql.connector

# Configuración de la conexión a tu base de datos local
db_config = {
    'host': 'localhost',
    'port': 3306,
    'user': 'root',
    'password': 'root',
    'database': 'hotel_db'
}

def ejecutar_carga_masiva():
    print("Conectando a la base de datos...")
    conn = mysql.connector.connect(**db_config)
    cursor = conn.cursor()

    try:
        # 1. Optimización: Desactivar verificación de claves foráneas temporalmente
        print("Desactivando restricciones de claves foráneas para optimizar la velocidad...")
        cursor.execute("SET FOREIGN_KEY_CHECKS = 0;")
        cursor.execute("SET autocommit = 0;") # Control manual de transacciones

        total_registros = 6000000
        lote_tamano = 10000
        total_lotes = total_registros // lote_tamano

        print(f"Iniciando la carga masiva de {total_registros} registros en {total_lotes} lotes...")

        # Asumimos rangos existentes en tus tablas maestras
        # (Ej: tienes huéspedes del 1 al 500000 y habitaciones del 1 al 5000)
        min_huesped = 1
        max_huesped = 500000 
        min_habitacion = 1
        max_habitacion = 5000

        estados = ['Confirmada', 'Finalizada', 'Cancelada']
        pesos_estados = [0.20, 0.65, 0.15] # 65% finalizadas, 20% confirmadas, 15% canceladas

        fecha_base = date(2023, 1, 1)

        for lote in range(1, total_lotes + 1):
            registros_lote = []
            
            for _ in range(lote_tamano):
                id_hab = random.randint(min_habitacion, max_habitacion)
                id_hue = random.randint(min_huesped, max_huesped)
                
                # Generar fechas coherentes
                dias_inicio = random.randint(0, 1000)
                duracion = random.randint(1, 7) # estadías de 1 a 7 días
                
                f_inicio = fecha_base + timedelta(days=dias_inicio)
                f_fin = f_inicio + timedelta(days=duracion)
                
                estado = random.choices(estados, weights=pesos_estados)[0]

                registros_lote.append((id_hab, id_hue, f_inicio, f_fin, estado))

            # Consulta SQL preparada para inserción masiva
            sql = """
                INSERT INTO Reserva (id_habitacion, id_huesped, fecha_inicio, fecha_fin, estado_reserva)
                VALUES (%s, %s, %s, %s, %s)
            """
            
            cursor.executemany(sql, registros_lote)
            conn.commit() # Confirmar el lote actual para liberar logs

            print(f"Lote {lote}/{total_lotes} insertado correctamente ({lote * lote_tamano} registros acumulados).")

        # Reactivar claves foráneas y autocommit
        print("Restaurando restricciones de integridad...")
        cursor.execute("SET FOREIGN_KEY_CHECKS = 1;")
        cursor.execute("SET autocommit = 1;")
        print("¡Carga masiva completada con éxito!")

    except Exception as e:
        conn.rollback()
        print(f"Error durante la carga masiva: {e}")
    finally:
        cursor.close()
        conn.close()

if __name__ == '__main__':
    ejecutar_carga_masiva()