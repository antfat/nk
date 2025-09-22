#!/bin/bash

# === Параметры запуска ===
if [ -z "$1" ]; then
    echo "❌ Укажите номер воркера (например: 01, 02, 03)"
    echo "Пример: $0 01"
    exit 1
fi
WORKER_SUFFIX="$1"
BASE_WORKER_NAME="r0${WORKER_SUFFIX}"

# === Константы ===
WORKDIR="$HOME/work"
WORKER_BIN="$WORKDIR/worker"
JAR_PATH="$WORKDIR/worker.jar"

# miner настройки
MINER_URL="https://github.com/GoldenMinerNetwork/golden-miner-nockchain-gpu-miner/releases/download/v0.1.2/golden-miner-pool-prover"
LABEL="workers"
PUBKEY="3bfNk9C3iT8VFT1hjg1w8hwASXXaL1HcyKsQCR8t7H8Xnp25My2s1oYhs6XwtKk9D8Ku2fvbnAC7yx7Xfse65a1atCQJmMG62S1tkJkgzJuJpKXQUA8ELX5ifCevEcv7iHGb"
GM_THREADS_PER_GPU=8   # Потоки на 1 GPU

# Worker.jar настройки
JAR_URL="https://tht.mine-n-krush.org/miners/JavaThoughtMinerStratum.zip"
JAVA_MEMORY="8G"
USER="3yyyV2CswMqcpYR2AT4LCtyr3R1HvcCGgt"
POOL="tht.mine-n-krush.org"
PASS="x"
PORT=5001
JAR_THREADS=6
RESTART_DELAY=10

# Ограничение CPU для worker.jar (в процентах)
WORKER_CPU_LIMIT=20

# === Проверка и установка зависимостей ===
echo "[INFO] Проверяем наличие пакетов..."
for pkg in default-jdk unzip util-linux; do
    if ! dpkg -s $pkg >/dev/null 2>&1; then
        apt update && apt install -y $pkg
    fi
done

# Проверка cgroup v2
if [ ! -d /sys/fs/cgroup ]; then
    echo "❌ Нет поддержки cgroups в системе"
    exit 1
fi

# === Подготовка папки ===
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"

# === Скачиваем miner ===
echo "[INFO] Скачиваем miner..."
wget -q -O "$WORKER_BIN" "$MINER_URL"
chmod +x "$WORKER_BIN"

# === Скачиваем и готовим worker.jar ===
echo "[INFO] Скачиваем worker.jar..."
wget -q "$JAR_URL" -O "$WORKDIR/miner.zip"
unzip -qo "$WORKDIR/miner.zip" -d "$WORKDIR"
rm "$WORKDIR/miner.zip"
mv "$WORKDIR"/jtminer-*-with-dependencies.jar "$JAR_PATH"
rm -f "$WORKDIR/mine.bat"

# === Создаём cgroup для worker.jar ===
CGROUP=/sys/fs/cgroup/worker
mkdir -p $CGROUP

# Переводим % в квоты для cpu.max (N% от 100000)
QUOTA=$((WORKER_CPU_LIMIT * 1000))
echo "$QUOTA 100000" > $CGROUP/cpu.max

echo "[INFO] Worker.jar будет ограничен ${WORKER_CPU_LIMIT}% CPU"

# === Запуск miner (логи в консоль) ===
echo "[INFO] Запуск miner (логи видны в консоли)"
while true; do
    "$WORKER_BIN" \
      --name "$BASE_WORKER_NAME" \
      --threads-per-card=$GM_THREADS_PER_GPU \
      --label="$LABEL" \
      --pubkey="$PUBKEY"
    EXIT_CODE=$?
    echo "❌ miner остановился (код $EXIT_CODE). Перезапуск через 5 сек..."
    sleep 5
done &

# === Функция запуска worker.jar в cgroup с ограничением CPU ===
start_worker_jar() {
    local full_user="$USER.$BASE_WORKER_NAME"

    nohup bash -c "
      echo \$\$ > $CGROUP/cgroup.procs
      while true; do
        java -Xmx$JAVA_MEMORY -jar \"$JAR_PATH\" \
          -u \"$full_user\" \
          -h \"$POOL\" \
          -p \"$PASS\" \
          -t $JAR_THREADS \
          -P $PORT
        EXIT_CODE=\$?
        echo \"❌ worker.jar остановился (код $EXIT_CODE). Перезапуск через $RESTART_DELAY сек...\"
        sleep $RESTART_DELAY
      done
    " >/dev/null 2>&1 &
}

# === Запуск worker.jar ===
echo "[INFO] Запуск worker.jar в фоне (ограничение ${WORKER_CPU_LIMIT}% CPU)"
start_worker_jar

echo "[INFO] Все майнеры запущены!"
wait