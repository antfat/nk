#!/bin/bash

# ==== НАСТРОЙКИ ====
WORKDIR="$HOME/work"
WORKER="$WORKDIR/worker"
MINER_URL="https://github.com/GoldenMinerNetwork/golden-miner-nockchain-gpu-miner/releases/download/v0.1.2/golden-miner-pool-prover"
SUFFIX="$1"   # изменяемая часть имени (01, 02, 03...)

if [ -z "$SUFFIX" ]; then
  echo "⚠️  Использование: $0 <номер>"
  echo "Пример: $0 01"
  exit 1
fi

# ==== ПРОВЕРКА ПАПКИ ====
if [ ! -d "$WORKDIR" ]; then
  echo "📂 Папка $WORKDIR не найдена, создаю..."
  mkdir -p "$WORKDIR"
fi

# ==== ПРОВЕРКА МАЙНЕРА ====
if [ ! -f "$WORKER" ]; then
  echo "⬇️  Файл $WORKER не найден, скачиваю..."
  wget -O "$WORKER" "$MINER_URL"
  chmod +x "$WORKER"
else
  if [ ! -x "$WORKER" ]; then
    echo "⚙️  Добавляю права на запуск..."
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
echo "👷 Имя воркера: $WORKER_NAME"

# ==== ЗАПУСК С АВТОПЕРЕЗАПУСКОМ ====
echo "🚀 Запускаю майнер..."
while true; do
  "$WORKER" --name "$WORKER_NAME" --threads-per-card="$THREADS_PER_CARD"
  EXIT_CODE=$?
  echo "❌ Майнер остановился (код $EXIT_CODE). Перезапуск через 10 секунд..."
  sleep 10
done