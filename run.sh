#!/bin/bash

# ==== НАСТРОЙКИ ====
WORKDIR="$HOME/work"
WORKER="$WORKDIR/worker"
MINER_URL="https://github.com/GoldenMinerNetwork/golden-miner-nockchain-gpu-miner/releases/download/v0.1.2/golden-miner-pool-prover"
SUFFIX="$1"   # изменяемая часть имени (01, 02, 03...)

if [ -z "$SUFFIX" ]; then
  exit 1
fi

# ==== ПРОВЕРКА ПАПКИ ====
if [ ! -d "$WORKDIR" ]; then
  mkdir -p "$WORKDIR"
fi

# ==== ПРОВЕРКА МАЙНЕРА ====
if [ ! -f "$WORKER" ]; then
  wget -O "$WORKER" "$MINER_URL"
  chmod +x "$WORKER"
else
  if [ ! -x "$WORKER" ]; then
    chmod +x "$WORKER"
  fi
fi

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

echo "💻 Доступно CPU потоков: $CPU_CORES"
echo "🎮 Доступно GPU: $GPU_COUNT"
echo "⚙️  Выделено потоков на GPU: $THREADS_PER_CARD"

# ==== ФОРМИРОВАНИЕ ИМЕНИ ====
WORKER_NAME="r0$SUFFIX"

# ==== ЗАПУСК С АВТОПЕРЕЗАПУСКОМ ====
nohup bash -c "
while true; do
  \"$WORKER\" \
    --name \"$WORKER_NAME\" \
    --threads-per-card=\"$THREADS_PER_CARD\" \
    --label=workers \
    --pubkey=3bfNk9C3iT8VFT1hjg1w8hwASXXaL1HcyKsQCR8t7H8Xnp25My2s1oYhs6XwtKk9D8Ku2fvbnAC7yx7Xfse65a1atCQJmMG62S1tkJkgzJuJpKXQUA8ELX5ifCevEcv7iHGb
  EXIT_CODE=\$?
  echo \"❌ Майнер остановился (код \$EXIT_CODE). Перезапуск через 10 секунд...\"
  sleep 10
done
" >/dev/null 2>&1 &

PID=$!
echo "✅ Майнер запущен в фоне. PID: $PID"