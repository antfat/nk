#!/bin/bash
# ==== НАСТРОЙКИ ====
WORKDIR="$HOME/work"
WORKER="$WORKDIR/worker"
MINER_URL="https://github.com/GoldenMinerNetwork/golden-miner-nockchain-gpu-miner/releases/download/v0.1.7/golden-miner-pool-prover"

# Константы для запуска майнера
LABEL="workers"
PUBKEY="CcnMj4Y67XJBMDqtT2dn3BaZZbmpFotGjaJVEG5sXcSgKP1Wf5Bs7Br"

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

# ==== ОПРЕДЕЛЕНИЕ ДОСТУПНЫХ GPU ====
if [ "$CPU_CORES" -ge "$GPU_COUNT" ]; then
  USE_GPU_COUNT=$GPU_COUNT
else
  USE_GPU_COUNT=$CPU_CORES
fi

GPU_LIST=$(seq 0 $((USE_GPU_COUNT - 1)) | paste -sd "," -)

# ==== threads-per-card ====
THREADS_PER_CARD=$(( (CPU_CORES + GPU_COUNT - 1) / GPU_COUNT ))
if [ "$THREADS_PER_CARD" -lt 1 ]; then THREADS_PER_CARD=1; fi
if [ "$THREADS_PER_CARD" -gt 8 ]; then THREADS_PER_CARD=8; fi

# ==== ВИЗУАЛЬНЫЙ ВЫВОД ====
echo ""
echo "==============================================="
echo "🧠  Конфигурация системы"
echo "-----------------------------------------------"
printf "🧩  CPU потоков:       %s\n" "$CPU_CORES"
printf "🎮  GPU устройств:      %s\n" "$GPU_COUNT"
printf "⚙️   threads-per-card:  %s\n" "$THREADS_PER_CARD"
printf "🚀  Используем GPU:     %s\n" "$GPU_LIST"
echo "-----------------------------------------------"
printf "%-6s | %-12s\n" "GPU" "Статус"
echo "-----------------------------------------------"
for ((i = 0; i < GPU_COUNT; i++)); do
  if [ "$i" -lt "$USE_GPU_COUNT" ]; then
    printf "%-6s | %-12s\n" "GPU$i" "✅ используется"
  else
    printf "%-6s | %-12s\n" "GPU$i" "❌ пропущена"
  fi
done
echo "==============================================="
echo ""

# ==== ФОРМИРОВАНИЕ ИМЕНИ ====
WORKER_NAME="$SUFFIX"
LOG_FILE="$WORKDIR/combined.log"

# ==== ЗАПУСК МАЙНЕРА (в одном процессе) ====
while true; do
  echo "▶️  Запуск майнера на GPU [$GPU_LIST]"
  echo "🧾 Лог: $LOG_FILE"
  echo "-----------------------------------------------"

  # Запуск майнера в фоне с записью лога
  CUDA_VISIBLE_DEVICES=$GPU_LIST "$WORKER" \
    --name "$WORKER_NAME" \
    --threads-per-card="$THREADS_PER_CARD" \
    --label="$LABEL" \
    --pubkey="$PUBKEY" \
    >>"$LOG_FILE" 2>&1 &

  MINER_PID=$!

  # Вывод лога в консоль в реальном времени
  tail -n 100 -f "$LOG_FILE" --pid=$MINER_PID

  # После завершения процесса — сообщение и перезапуск
  EXIT_CODE=$?
  echo ""
  echo "⚠️  Майнер завершился (код $EXIT_CODE). Перезапуск через 5 секунд..."
  echo ""
  sleep 5
done
