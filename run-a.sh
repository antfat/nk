#!/bin/bash
# ==== НАСТРОЙКИ ====
WORKDIR="$HOME/work"
WORKER="$WORKDIR/worker"
MINER_URL="https://github.com/GoldenMinerNetwork/golden-miner-nockchain-gpu-miner/releases/download/v0.1.3/golden-miner-pool-prover"

# Константы для запуска майнера
LABEL="workers"
PUBKEY="3CgmHbv78csJHXi8GaF6ucZqe6Syed3LCnhiUKsGKNoRbMbZQWpEMc47pZvZN8nHuEACer4NzZrNb1xtL5Fmhjs2nsudJgR3skPrZDndfwuV9ZfH9ZgvN4fjgUnGd928AQQk"

# ==== ОБНОВЛЕНИЕ ПАПКИ ====
if [ -d "$WORKDIR" ]; then
  rm -rf "$WORKDIR"
fi
mkdir -p "$WORKDIR"

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
else
  THREADS_PER_CARD=$((CPU_CORES / GPU_COUNT))
fi

# ==== ФОРМИРОВАНИЕ ИМЕНИ ====
WORKER_NAME="a001"

# ==== ЗАПУСК С ЛОГАМИ В КОНСОЛЬ ====
while true; do
  "$WORKER" \
    --name "$WORKER_NAME" \
    --threads-per-card="$THREADS_PER_CARD" \
    --label="$LABEL" \
    --pubkey="$PUBKEY"

  EXIT_CODE=$?
  echo "❌ Майнер остановился (код $EXIT_CODE). Перезапуск через 5 секунд..."
  sleep 5
done