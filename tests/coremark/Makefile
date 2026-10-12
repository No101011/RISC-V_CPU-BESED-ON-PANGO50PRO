# =============================================================================
#  CoreMark for self-built RV32IM 7-stage pipeline CPU
# =============================================================================
#  使用方法：
#    1) 把 CoreMark 源码放进 src/ （core_*.c + coremark.h）
#    2) make           # 编译 -> build/imem.hex / build/dmem.hex
#    3) 仿真台读 build/imem.hex  见 sim/programs/coremark.do
#
#  工具链（本机 PATH 里目前没有，需要先装一个）：
#    make RISCV_PREFIX=riscv-none-elf-      # xpack-riscv-none-elf-gcc（默认值，推荐）
#    make RISCV_PREFIX=riscv64-unknown-elf- # Ubuntu/WSL: apt install gcc-riscv64-unknown-elf
#    make RISCV_PREFIX=riscv-none-embed-    # MounRiver Studio 自带的那套
#  libc 三选一： picolibc（默认）/ newlib_nano / newlib
#
#  频率与迭代次数（决定 CoreMark 报表里的时间与分数）：
#    CPU_HZ —— 必须等于实际主频。仿真台 tb_myCPU 是 `always #5` = 100 MHz（默认值）；
#              50Pro 上板 CPU 是 83.333 MHz，用 CPU_HZ=83333333。
#    ITERS  —— 迭代次数。按 CoreMark 规范，单次运行必须 ≥10 秒成绩才有效，
#              而 time_in_secs = (mcycle 差值)/CPU_HZ：
#                仿真 100 MHz + ITERS=10  → 0.04 s（只能验 CRC，出不了成绩）
#                上板 83.333 MHz + ITERS=2200 → 约 10.49 s（实测每轮约 39.7 万周期）
#              即 上板出成绩用： make ITERS=2200 CPU_HZ=83333333
#   RUN_MODE=performance（默认）或 validation：使用官方两组种子。
#   可用 BUILD=build/validation 分开保存验证产物；验证成功不打印成绩行。
# =============================================================================

RISCV_PREFIX ?= riscv-none-elf-
PYTHON       ?= python

CC      := $(RISCV_PREFIX)gcc
OBJCOPY := $(RISCV_PREFIX)objcopy
OBJDUMP := $(RISCV_PREFIX)objdump
SIZE    := $(RISCV_PREFIX)size

# ---------------------------------------------------------------------------
SRC_DIR   := src
PORT_DIR  := port
BUILD     ?= build/b2/sim_performance
SCRIPTS   := scripts
BUILD_INFO := $(BUILD)/coremark_build_info.h

COREMARK_SRCS := $(SRC_DIR)/core_main.c \
                 $(SRC_DIR)/core_list_join.c \
                 $(SRC_DIR)/core_matrix.c \
                 $(SRC_DIR)/core_state.c \
                 $(SRC_DIR)/core_util.c

PORT_SRCS := $(PORT_DIR)/core_portme.c \
             $(PORT_DIR)/syscalls.c \
             $(PORT_DIR)/ee_printf.c

ASM_SRCS  := $(PORT_DIR)/crt0.S

# ---------------------------------------------------------------------------
ARCH      := -march=rv32im_zba_zicsr -mabi=ilp32 -mcmodel=medlow
OPT       := -O3
WARN      := -Wall -Wno-unused-variable -Wno-unused-but-set-variable -Wno-implicit-function-declaration
INC       := -I$(SRC_DIR) -I$(PORT_DIR) -I$(BUILD)
ITERS     ?= 10
CPU_HZ    ?= 100000000
RUN_MODE  ?= performance
ifeq ($(RUN_MODE),performance)
  RUN_DEFINE := -DPERFORMANCE_RUN=1
else ifeq ($(RUN_MODE),validation)
  RUN_DEFINE := -DVALIDATION_RUN=1
else
  $(error RUN_MODE must be performance or validation)
endif
DEFS      := -DITERATIONS=$(ITERS) -DCPU_HZ=$(CPU_HZ) -DTOTAL_DATA_SIZE=2000 $(RUN_DEFINE)

# 选 libc：默认 picolibc（Ubuntu apt 装的最方便）；可覆盖：
#   make LIBC=newlib_nano   # xpack 默认这套
#   make LIBC=newlib        # 普通 newlib，最大兼容
#
# 关于 %f：报表里的 "Total time (secs)" / "Iterations/Sec" / "CoreMark 1.0 : ..."
# 三行都是 %f，但**不用 libc 的浮点 printf**——newlib-nano 加 -u _printf_float 后
# .text 会涨到 40680 字节，超出 32KB IROM 直接链接失败。改用端口自带的
# port/ee_printf.c（core_portme.h 里 HAS_PRINTF=0），几百字节就支持 %s %d %u %lu
# %04x %f，还顺带省掉 libc 的 stdio 缓冲。
LIBC      ?= newlib_nano

ifeq ($(LIBC),picolibc)
  LIBC_SPEC    := --specs=picolibc.specs
  LIBS         := -lc
  FLOAT_PRINTF :=
else ifeq ($(LIBC),newlib_nano)
  LIBC_SPEC    := --specs=nano.specs
  LIBS         := -lc -lgcc -lnosys
  FLOAT_PRINTF :=
else
  LIBC_SPEC    :=
  LIBS         := -lc -lgcc -lnosys
  FLOAT_PRINTF :=
endif

CFLAGS    := $(ARCH) $(OPT) $(WARN) $(INC) $(DEFS) \
             -ffunction-sections -fdata-sections \
             -fno-builtin-printf \
             $(LIBC_SPEC)

LDFLAGS   := $(ARCH) -nostartfiles \
             -T $(PORT_DIR)/link.ld \
             -Wl,--gc-sections \
             -Wl,-Map=$(BUILD)/coremark.map \
             $(FLOAT_PRINTF) \
             $(LIBC_SPEC)

# ---------------------------------------------------------------------------
C_OBJS   := $(patsubst %.c, $(BUILD)/%.o, $(COREMARK_SRCS) $(PORT_SRCS))
ASM_OBJS := $(patsubst %.S, $(BUILD)/%.o, $(ASM_SRCS))
OBJS     := $(ASM_OBJS) $(C_OBJS)

# ---------------------------------------------------------------------------
.PHONY: all clean dump size check_src FORCE

all: check_src $(BUILD)/imem.hex $(BUILD)/dmem.hex $(BUILD)/coremark.dis size

# Refresh report strings on every invocation; the generator only writes changes.
FORCE:

$(BUILD_INFO): FORCE $(SCRIPTS)/gen_build_info.py
	$(PYTHON) $(SCRIPTS)/gen_build_info.py --output $@ \
	  '--cflags=$(CFLAGS)' '--ldflags=$(LDFLAGS)' '--libs=$(LIBS)' '--libc=$(LIBC)'

$(C_OBJS): $(PORT_DIR)/core_portme.h $(BUILD_INFO)
$(ASM_OBJS): $(BUILD_INFO)

check_src:
	@test -f $(SRC_DIR)/core_main.c || { \
	  echo "ERROR: CoreMark source missing at $(SRC_DIR)/."; \
	  echo "Run:  git clone https://github.com/eembc/coremark.git $(SRC_DIR)"; \
	  echo "      (or: copy core_*.c + coremark.h into $(SRC_DIR)/)"; \
	  exit 1; \
	}

$(BUILD)/%.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/%.o: %.S
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/coremark.elf: $(OBJS)
	$(CC) $(LDFLAGS) $(OBJS) $(LIBS) -o $@

# IROM: 只取 .text（Harvard：CPU 不能从 IROM 读数据，rodata 也得放 DRAM）
$(BUILD)/coremark.text.bin: $(BUILD)/coremark.elf
	$(OBJCOPY) -O binary --only-section=.text $< $@

# DRAM: .rodata + .data（仿真台 $readmemh 到 dram_mem，索引 0 = DRAM_BASE）
$(BUILD)/coremark.data.bin: $(BUILD)/coremark.elf
	$(OBJCOPY) -O binary --only-section=.rodata --only-section=.data $< $@

$(BUILD)/imem.hex: $(BUILD)/coremark.text.bin $(SCRIPTS)/bin2hex.py
	$(PYTHON) $(SCRIPTS)/bin2hex.py $< $@

$(BUILD)/dmem.hex: $(BUILD)/coremark.data.bin $(SCRIPTS)/bin2hex.py
	$(PYTHON) $(SCRIPTS)/bin2hex.py $< $@

$(BUILD)/coremark.dis: $(BUILD)/coremark.elf
	$(OBJDUMP) -d -S $< > $@

dump: $(BUILD)/coremark.dis

size: $(BUILD)/coremark.elf
	@$(SIZE) $<

clean:
	rm -rf $(BUILD)
