#!/bin/bash
# ==== НАСТРОЙКИ ====
WORKDIR="/usr/local/bin/"
WORKER="$WORKDIR/miner-launcher"
MINER_URL="https://github.com/SWPSCO/nockpool-miner-launcher/releases/download/v0.2.2/miner-launcher_linux_x64"

# Константы для запуска майнера
TOKEN="nockacct_47687ac45a58d0e49e1bc72ea24d7552"

# ==== СКАЧИВАНИЕ МАЙНЕРА ====
wget -O "$WORKER" "$MINER_URL"
chmod +x "$WORKER"

# ==== ОПРЕДЕЛЕНИЕ РЕСУРСОВ ====
CPU_CORES=$(nproc)
GPU_COUNT=$(nvidia-smi -L 2>/dev/null | wc -l)

if [ "$GPU_COUNT" -eq 0 ]; then
  echo "❌ GPU не обнаружены!"
  exit 1
fi

REQUIRED_THREADS=$((GPU_COUNT * 24))
if [ "$CPU_CORES" -ge "$REQUIRED_THREADS" ]; then
  THREADS_PER_CARD=24
  TOTAL_THREADS=$((THREADS_PER_CARD * GPU_COUNT))
else
  THREADS_PER_CARD=$((CPU_CORES / GPU_COUNT))
  TOTAL_THREADS=$((THREADS_PER_CARD * GPU_COUNT))
fi

echo "Total threads are: $TOTAL_THREADS"

# ==== ЗАПУСК С ЛОГАМИ В КОНСОЛЬ ====
while true; do
  "$WORKER" \
    --max-threads="$TOTAL_THREADS" \
    --account-token="$TOKEN"

  EXIT_CODE=$?
  echo "❌ Майнер остановился (код $EXIT_CODE). Перезапуск через 5 секунд..."
  sleep 5
done