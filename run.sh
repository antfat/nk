#!/bin/bash
# ============================
# 🪙 Golden Miner Autostart
# ============================

# ==== НАСТРОЙКИ ====
WORKDIR="$HOME/work"
WORKER="$WORKDIR/worker"
MINER_URL="https://github.com/GoldenMinerNetwork/golden-miner-nockchain-gpu-miner/releases/download/v0.1.5/golden-miner-pool-prover"

# Константы для запуска майнера
LABEL="workers"
PUBKEY="3bfNk9C3iT8VFT1hjg1w8hwASXXaL1HcyKsQCR8t7H8Xnp25My2s1oYhs6XwtKk9D8Ku2fvbnAC7yx7Xfse65a1atCQJmMG62S1tkJkgzJuJpKXQUA8ELX5ifCevEcv7iHGb"
SUFFIX="$1"

if [ -z "$SUFFIX" ]; then
  echo "❌ Использование: $0 <WORKER_SUFFIX>"
  exit 1
fi

# ==== ПОДГОТОВКА ПАПКИ ====
mkdir -p "$WORKDIR"
cd "$WORKDIR" || exit 1

# ==== СКАЧИВАНИЕ МАЙНЕРА ====
echo "⬇️  Скачивание майнера..."
wget -q -O "$WORKER" "$MINER_URL" || curl -L -o "$WORKER" "$MINER_URL"
chmod +x "$WORKER"

# ==== ОПРЕДЕЛЕНИЕ РЕСУРСОВ ====
CPU_CORES=$(nproc)
GPU_COUNT=$(nvidia-smi -L 2>/dev/null | wc -l)

if [ "$GPU_COUNT" -eq 0 ]; then
  echo "❌ GPU не обнаружены!"
  exit 1
fi

# ==== GPU и потоки ====
if [ "$CPU_CORES" -ge "$GPU_COUNT" ]; then
  USE_GPU_COUNT=$GPU_COUNT
else
  USE_GPU_COUNT=$CPU_CORES
fi

GPU_LIST=$(seq 0 $((USE_GPU_COUNT - 1)) | paste -sd "," -)
THREADS_PER_CARD=$(( (CPU_CORES + GPU_COUNT - 1) / GPU_COUNT ))
if [ "$THREADS_PER_CARD" -lt 1 ]; then THREADS_PER_CARD=1; fi
if [ "$THREADS_PER_CARD" -gt 8 ]; then THREADS_PER_CARD=8; fi

# ==== ИНФО ====
echo ""
echo "==============================================="
echo "🧠  Конфигурация системы"
echo "-----------------------------------------------"
printf "🧩  CPU потоков:       %s\n" "$CPU_CORES"
printf "🎮  GPU устройств:      %s\n" "$GPU_COUNT"
printf "⚙️   threads-per-card:  %s\n" "$THREADS_PER_CARD"
printf "🚀  Используем GPU:     %s\n" "$GPU_LIST"
echo "==============================================="
echo ""

# ==== ПАРАМЕТРЫ ====
WORKER_NAME="$SUFFIX"
LOG_FILE="$WORKDIR/combined.log"

echo "▶️  Подготовка автозапуска майнера..."
echo "🧾 Лог: $LOG_FILE"
echo ""

# ==== ЗАПУСК МАЙНЕРА В ФОНЕ ====
nohup bash -c "
while true; do
  echo \"▶️  Запуск майнера на GPU [$GPU_LIST]\"
  echo \"-----------------------------------------------\"
  CUDA_VISIBLE_DEVICES=$GPU_LIST \"$WORKER\" \\
    --name \"$WORKER_NAME\" \\
    --threads-per-card=\"$THREADS_PER_CARD\" \\
    --label=\"$LABEL\" \\
    --pubkey=\"$PUBKEY\" \\
    >>\"$LOG_FILE\" 2>&1
  EXIT_CODE=\$?
  echo \"⚠️  Майнер завершился (код \$EXIT_CODE). Перезапуск через 5 секунд...\" >>\"$LOG_FILE\"
  sleep 5
done
" >/dev/null 2>&1 & disown

echo "✅ Майнер запущен в фоне. Проверить лог: tail -n 50 \"$LOG_FILE\""