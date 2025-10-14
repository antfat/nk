#!/bin/bash
# =====================================================
# 🚀 Universal GPU Miner Launcher for Ubuntu 24 / HiveOS
# =====================================================
# • Проверяет ≥32 CPU ядер и ≥45 ГБ RAM на GPU (с предупреждением)  # (опционально/информативно)
# • Полностью пересоздаёт каталог $HOME/work
# • Скачивает майнер и ставит права
# • Запускает отдельный процесс для каждой GPU (при достаточном количестве CPU и RAM)
# • GPU 0 — с live tail логом
# • Остальные — фоново с авто-рестартом
# • Лог-ротация: при >50 МБ лог очищается
# =====================================================

# === Проверка параметра ===
if [ -z "$1" ]; then
  echo "❌ Использование: $0 <WORKER_NAME>"
  exit 1
fi
WORKER_NAME="$1"

# === Константы ===
POOL_URL="stratum+tcp://neptune.drpool.io:30127"
BASE_DIR="$HOME/work"
MINER_TAR="ubuntu_20-dr_neptune_prover-3.2.0.tar.gz"
MINER_URL="https://pub-e1b06c9c8c3f481d81fa9619f12d0674.r2.dev/image/v2/$MINER_TAR"
WORK_DIR="$BASE_DIR/worker"

MIN_CPU_PER_GPU=28   # минимум физических ядер на 1 GPU
MIN_RAM_PER_GPU=42   # минимум ГБ RAM на 1 GPU

# === Проверка системных параметров ===
TOTAL_RAM_GB=$(free -g | awk '/Mem:/ {print $2}')
# логические CPU (для taskset/разбивки диапазонов):
CPU_CORES=$(nproc)
# физические ядра (для проверки ёмкости):
PHYS_CORES=$(lscpu -p=Core,Socket | grep -v '^#' | sort -u | wc -l)
GPU_COUNT=$(nvidia-smi -L | wc -l)

# === Подготовка папки ===
echo "🧹 Очистка и подготовка каталога $BASE_DIR..."
rm -rf "$BASE_DIR"
mkdir -p "$BASE_DIR"
cd "$BASE_DIR" || exit 1

# === Установка майнера ===
echo "⬇️  Скачивание майнера..."
wget -q "$MINER_URL" -O "$MINER_TAR"
tar -xzf "$MINER_TAR"
rm -f "$MINER_TAR"
mv dr_neptune_prover worker
chmod +x "$WORK_DIR"/*
cd "$WORK_DIR" || exit 1

# === Функция лог-ротации ===
rotate_log() {
  local LOG_FILE="$1"
  local MAX_SIZE_MB=50
  if [ -f "$LOG_FILE" ]; then
    local SIZE_MB
    SIZE_MB=$(du -m "$LOG_FILE" | awk '{print $1}')
    if [ "$SIZE_MB" -gt "$MAX_SIZE_MB" ]; then
      echo "🧾 Лог $LOG_FILE превышает ${MAX_SIZE_MB} МБ — очищается..."
      : >"$LOG_FILE"
    fi
  fi
}

# === Функция запуска майнера с авто-рестартом ===
run_miner() {
  local GPU_ID=$1
  local START_CORE=$2
  local END_CORE=$3
  local LOG_FILE="guesser_${GPU_ID}.log"

  while true; do
    rotate_log "$LOG_FILE"
    if [ -n "$START_CORE" ] && [ -n "$END_CORE" ]; then
      echo "▶️  Запуск GPU ${GPU_ID} (логич. CPU ${START_CORE}-${END_CORE})..."
      taskset -c ${START_CORE}-${END_CORE} ./dr_neptune_prover -p "$POOL_URL" -w "mustfun.${WORKER_NAME}" -g "$GPU_ID" >>"$LOG_FILE" 2>&1
    else
      echo "▶️  Запуск GPU ${GPU_ID} (без привязки к CPU)..."
      ./dr_neptune_prover -p "$POOL_URL" -w "mustfun.${WORKER_NAME}" -g "$GPU_ID" >>"$LOG_FILE" 2>&1
    fi
    echo "⚠️  Процесс GPU ${GPU_ID} завершился — перезапуск через 5 секунд..."
    sleep 5
  done
}

# === Ёмкость по CPU и RAM (используем физические ядра!) ===
AVAILABLE_CPU_GPUS=$((PHYS_CORES / MIN_CPU_PER_GPU))
AVAILABLE_RAM_GPUS=$((TOTAL_RAM_GB / MIN_RAM_PER_GPU))

# Минимум из двух
if [ "$AVAILABLE_CPU_GPUS" -lt "$AVAILABLE_RAM_GPUS" ]; then
  AVAILABLE_GPUS=$AVAILABLE_CPU_GPUS
else
  AVAILABLE_GPUS=$AVAILABLE_RAM_GPUS
fi

# Нормируем по количеству реальных GPU и нижней границе 1
if [ "$AVAILABLE_GPUS" -lt 1 ]; then
  AVAILABLE_GPUS=1
fi
if [ "$AVAILABLE_GPUS" -gt "$GPU_COUNT" ]; then
  AVAILABLE_GPUS=$GPU_COUNT
fi

echo "⚙️  Физ. ядра: $PHYS_CORES (мин. $MIN_CPU_PER_GPU/процесс), RAM: ${TOTAL_RAM_GB}ГБ (мин. $MIN_RAM_PER_GPU/процесс)"
echo "➡️  Будет запущено процессов майнера: $AVAILABLE_GPUS из $GPU_COUNT GPU"

# === Распределение логических CPU между выбранными GPU ===
if [ "$AVAILABLE_GPUS" -gt 1 ]; then
  CORES_PER_GPU=$((CPU_CORES / AVAILABLE_GPUS))
else
  CORES_PER_GPU=$CPU_CORES
fi

CURRENT_START=0

# === Таблица статуса GPU (перед запуском) ===
echo ""
echo "==============================================="
printf "%-6s | %-15s | %-10s | %-10s\n" "GPU" "CPU диапазон" "RAM ОК" "Статус"
echo "-----------------------------------------------"
TMP_START=$CURRENT_START
for ((i = 0; i < GPU_COUNT; i++)); do
  if [ "$i" -lt "$AVAILABLE_GPUS" ]; then
    END=$((TMP_START + CORES_PER_GPU - 1))
    if [ "$END" -ge "$CPU_CORES" ]; then END=$((CPU_CORES - 1)); fi
    printf "%-6s | %-15s | %-10s | %-10s\n" "GPU${i}" "${TMP_START}-${END}" "✅" "Запуск"
    TMP_START=$((END + 1))
  else
    printf "%-6s | %-15s | %-10s | %-10s\n" "GPU${i}" "-" "❌" "Пропуск"
  fi
done
echo "==============================================="
echo ""

# === Запуск майнеров ===
echo "🚀 Запуск майнера..."
for ((i = 0; i < GPU_COUNT; i++)); do
  if [ "$i" -lt "$AVAILABLE_GPUS" ]; then
    END_CORE=$((CURRENT_START + CORES_PER_GPU - 1))
    if [ "$END_CORE" -ge "$CPU_CORES" ]; then
      END_CORE=$((CPU_CORES - 1))
    fi

    if [ "$i" -eq 0 ]; then
      run_miner "$i" "$CURRENT_START" "$END_CORE" &
      sleep 2
      tail -n 100 -f "guesser_${i}.log"
    else
      run_miner "$i" "$CURRENT_START" "$END_CORE" &
      sleep 1
    fi
    CURRENT_START=$((END_CORE + 1))
  else
    echo "⏭️  Пропуск GPU${i} (не хватает физ. ядер ≥${MIN_CPU_PER_GPU} и/или RAM ≥${MIN_RAM_PER_GPU}ГБ)"
  fi
done