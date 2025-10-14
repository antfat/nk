#!/bin/bash
# ==== НАСТРОЙКИ ====
WORKDIR="$HOME/work"
WORKER="$WORKDIR/worker"
MINER_URL="https://github.com/GoldenMinerNetwork/golden-miner-nockchain-gpu-miner/releases/download/v0.1.5/golden-miner-pool-prover"

# Константы для запуска майнера
LABEL="workers"
PUBKEY="3bfNk9C3iT8VFT1hjg1w8hwASXXaL1HcyKsQCR8t7H8Xnp25My2s1oYhs6XwtKk9D8Ku2fvbnAC7yx7Xfse65a1atCQJmMG62S1tkJkgzJuJpKXQUA8ELX5ifCevEcv7iHGb"

SUFFIX="$1"
if [ -z "$SUFFIX" ]; then
  echo "❌ Использование: $0 <SUFFIX>"
  exit 1
fi

# ==== ОБНОВЛЕНИЕ ПАПКИ ====
if [ -d "$WORKDIR" ]; then
  rm -rf "$WORKDIR"
fi
mkdir -p "$WORKDIR"

# ==== СКАЧИВАНИЕ МАЙНЕРА ====
wget -q -O "$WORKER" "$MINER_URL"
chmod +x "$WORKER"

# ==== ОПРЕДЕЛЕНИЕ РЕСУРСОВ ====
CPU_CORES=$(nproc)
GPU_COUNT=$(nvidia-smi -L 2>/dev/null | wc -l)

if [ "$GPU_COUNT" -eq 0 ]; then
  echo "❌ GPU не обнаружены!"
  exit 1
fi

# ==== РАВНОМЕРНОЕ РАСПРЕДЕЛЕНИЕ ПОТОКОВ (округление вверх) ====
THREADS_PER_CARD=$(( (CPU_CORES + GPU_COUNT - 1) / GPU_COUNT ))
if [ "$THREADS_PER_CARD" -lt 1 ]; then
  THREADS_PER_CARD=1
fi

# Ограничение максимум 8 потоков на карту
if [ "$THREADS_PER_CARD" -gt 8 ]; then
  echo "⚠️  Ограничение: рассчитано $THREADS_PER_CARD потоков на карту, установлено максимум 8."
  THREADS_PER_CARD=8
fi

# ==== ВИЗУАЛЬНЫЙ ВЫВОД ====
echo ""
echo "==============================================="
echo "🧠  Конфигурация системы"
echo "-----------------------------------------------"
printf "🧩  CPU потоков:       %s\n" "$CPU_CORES"
printf "🎮  GPU устройств:      %s\n" "$GPU_COUNT"
printf "⚙️   threads-per-card:  %s\n" "$THREADS_PER_CARD"
echo "==============================================="
echo ""

# ==== ФОРМИРОВАНИЕ ИМЕНИ ====
WORKER_NAME="$SUFFIX"

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
