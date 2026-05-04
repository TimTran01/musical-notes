#include "sleep.h"
#include "xgpio.h"
#include "xil_exception.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xscugic.h"
#include "xstatus.h"
#include "xuartps_hw.h"

#define NOTE_GPIO_STATUS_CHANNEL 1U
#define NOTE_GPIO_CLEAR_CHANNEL  2U
#define NOTE_CONTROL_CLEAR       0x1U
#define NOTE_CONTROL_PAGE_SHIFT  1U
#define NOTE_PENDING_MASK        0x80000000U
#define NOTE_KEY_SHIFT           24U
#define NOTE_KEY3_SHIFT          17U
#define NOTE_KEY12_SHIFT         10U
#define NOTE_KEY48_SHIFT         3U
#define NOTE_SELECTED_BANK_SHIFT 1U
#define NOTE_KEY_MASK            0x7FU
#define NOTE_SELECTED_BANK_MASK  0x3U
#define NOTE_POWER_EXP_MASK      0x7FU
#define NOTE_POWER_MANT_MASK     0xFFU
#define NOTE_QUEUE_LENGTH        16U
#define NOTE_POLL_DELAY_US       10000U
#define UART_COMMAND_LINE_LENGTH 64U
#define SAMPLE_LINE_LENGTH       16U
#define SAMPLE_BUFFER_WORDS      4096U
#define SAMPLE_WORD_MASK         0x00FFFFFFU
#define SAMPLE_PLAYER_CONTROL    0x0000U
#define SAMPLE_PLAYER_STATUS     0x0004U
#define SAMPLE_PLAYER_COUNT      0x0008U
#define SAMPLE_PLAYER_DATA       0x1000U
#define SAMPLE_CONTROL_ENABLE    0x00000001U
#define SAMPLE_CONTROL_RESTART   0x00000002U
#define UART_POLL_DELAY_US       100U
#define UART_LINE_TIMEOUT_POLLS  30000U

#if defined(SDT) && defined(XPAR_NOTE_AXI_GPIO_0_BASEADDR)
#define NOTE_GPIO_DEVICE_ID XPAR_NOTE_AXI_GPIO_0_BASEADDR
#elif defined(SDT) && defined(XPAR_XGPIO_0_BASEADDR)
#define NOTE_GPIO_DEVICE_ID XPAR_XGPIO_0_BASEADDR
#elif defined(XPAR_NOTE_AXI_GPIO_0_DEVICE_ID)
#define NOTE_GPIO_DEVICE_ID XPAR_NOTE_AXI_GPIO_0_DEVICE_ID
#elif defined(XPAR_AXI_GPIO_0_DEVICE_ID)
#define NOTE_GPIO_DEVICE_ID XPAR_AXI_GPIO_0_DEVICE_ID
#else
#error "Could not find AXI GPIO identifier for note_axi_gpio_0 in xparameters.h"
#endif

#if defined(SDT) && defined(XPAR_XSCUGIC_0_BASEADDR)
#define NOTE_GIC_DEVICE_ID XPAR_XSCUGIC_0_BASEADDR
#elif defined(SDT) && defined(XPAR_INTC_BASEADDR)
#define NOTE_GIC_DEVICE_ID XPAR_INTC_BASEADDR
#elif defined(XPAR_SCUGIC_SINGLE_DEVICE_ID)
#define NOTE_GIC_DEVICE_ID XPAR_SCUGIC_SINGLE_DEVICE_ID
#elif defined(XPAR_PS7_SCUGIC_0_DEVICE_ID)
#define NOTE_GIC_DEVICE_ID XPAR_PS7_SCUGIC_0_DEVICE_ID
#elif defined(XPAR_SCUGIC_0_DEVICE_ID)
#define NOTE_GIC_DEVICE_ID XPAR_SCUGIC_0_DEVICE_ID
#else
#error "Could not find SCUGIC identifier in xparameters.h"
#endif

#if defined(XPAR_FABRIC_NOTE_EVENT_LATCH_0_IRQ_INTR)
#define NOTE_IRQ_ID XPAR_FABRIC_NOTE_EVENT_LATCH_0_IRQ_INTR
#elif defined(XPAR_FABRIC_NOTE_EVENT_LATCH_0_IRQ)
#define NOTE_IRQ_ID XPAR_FABRIC_NOTE_EVENT_LATCH_0_IRQ
#elif defined(XPAR_FABRIC_IRQ_F2P_0_INTR)
#define NOTE_IRQ_ID XPAR_FABRIC_IRQ_F2P_0_INTR
#elif defined(XPAR_FABRIC_PROCESSING_SYSTEM7_0_IRQ_F2P_INTR)
#define NOTE_IRQ_ID XPAR_FABRIC_PROCESSING_SYSTEM7_0_IRQ_F2P_INTR
#elif defined(SDT)
/* Zynq-7000 IRQ_F2P[0] is GIC interrupt ID 61. */
#define NOTE_IRQ_ID 61U
#else
#error "Could not find PL note interrupt ID in xparameters.h"
#endif

#if defined(XPAR_AXI_ADC_SAMPLE_PLAYER_0_BASEADDR)
#define SAMPLE_PLAYER_BASEADDR XPAR_AXI_ADC_SAMPLE_PLAYER_0_BASEADDR
#elif defined(XPAR_AXI_ADC_SAMPLE_PLAYER_0_S_AXI_BASEADDR)
#define SAMPLE_PLAYER_BASEADDR XPAR_AXI_ADC_SAMPLE_PLAYER_0_S_AXI_BASEADDR
#elif defined(XPAR_AXI_ADC_SAMPLE_PLAYER_BASEADDR)
#define SAMPLE_PLAYER_BASEADDR XPAR_AXI_ADC_SAMPLE_PLAYER_BASEADDR
#else
/* connect_note_uart_bd.tcl fixes this address for the custom sample player. */
#define SAMPLE_PLAYER_BASEADDR 0x43C00000U
#endif

static XGpio NoteGpio;
static XScuGic InterruptController;

typedef struct {
    u8 key;
    u8 key3;
    u8 key12;
    u8 key48;
    u8 selected_bank;
    u8 power3_exp;
    u8 power3_mant;
    u8 power12_exp;
    u8 power12_mant;
    u8 power48_exp;
    u8 power48_mant;
} NoteEvent;

static volatile NoteEvent NoteQueue[NOTE_QUEUE_LENGTH];
static volatile u8 QueueHead = 0U;
static volatile u8 QueueTail = 0U;
static volatile u32 DroppedEvents = 0U;
static volatile u8 NoteOutputArmed = 0U;
static u32 NoteControlValue = 0U;

static u8 LastLevelKey = 0U;
static char CommandLine[UART_COMMAND_LINE_LENGTH];
static u32 CommandLength = 0U;

static const char *const NoteNames[89] = {
    "", "A0", "A#0", "B0", "C1", "C#1", "D1", "D#1", "E1", "F1", "F#1",
    "G1", "G#1", "A1", "A#1", "B1", "C2", "C#2", "D2", "D#2", "E2",
    "F2", "F#2", "G2", "G#2", "A2", "A#2", "B2", "C3", "C#3", "D3",
    "D#3", "E3", "F3", "F#3", "G3", "G#3", "A3", "A#3", "B3", "C4",
    "C#4", "D4", "D#4", "E4", "F4", "F#4", "G4", "G#4", "A4", "A#4",
    "B4", "C5", "C#5", "D5", "D#5", "E5", "F5", "F#5", "G5", "G#5",
    "A5", "A#5", "B5", "C6", "C#6", "D6", "D#6", "E6", "F6", "F#6",
    "G6", "G#6", "A6", "A#6", "B6", "C7", "C#7", "D7", "D#7", "E7",
    "F7", "F#7", "G7", "G#7", "A7", "A#7", "B7", "C8"
};

static const u32 NoteFreqCentiHz[89] = {
    0U, 2750U, 2914U, 3087U, 3270U, 3465U, 3671U, 3889U, 4120U, 4365U,
    4625U, 4900U, 5191U, 5500U, 5827U, 6174U, 6541U, 6930U, 7342U, 7778U,
    8241U, 8731U, 9250U, 9800U, 10383U, 11000U, 11654U, 12347U, 13081U,
    13859U, 14683U, 15556U, 16481U, 17461U, 18500U, 19600U, 20765U, 22000U,
    23308U, 24694U, 26163U, 27718U, 29366U, 31113U, 32963U, 34923U, 36999U,
    39200U, 41530U, 44000U, 46616U, 49388U, 52325U, 55437U, 58733U, 62225U,
    65926U, 69846U, 73999U, 78399U, 83061U, 88000U, 93233U, 98777U, 104650U,
    110873U, 117466U, 124451U, 131851U, 139691U, 147998U, 156798U, 166122U,
    176000U, 186466U, 197553U, 209300U, 221746U, 234932U, 248902U, 263702U,
    279383U, 295996U, 313596U, 332244U, 352000U, 372931U, 395107U, 418601U
};

static void PulseNoteClear(void)
{
    XGpio_DiscreteWrite(&NoteGpio, NOTE_GPIO_CLEAR_CHANNEL, NoteControlValue | NOTE_CONTROL_CLEAR);
    XGpio_DiscreteWrite(&NoteGpio, NOTE_GPIO_CLEAR_CHANNEL, NoteControlValue);
}

static void SelectDebugPage(u8 page)
{
    NoteControlValue = ((u32)(page & 0x3U) << NOTE_CONTROL_PAGE_SHIFT);
    XGpio_DiscreteWrite(&NoteGpio, NOTE_GPIO_CLEAR_CHANNEL, NoteControlValue);
}

static NoteEvent DecodeNoteStatus(u32 status)
{
    NoteEvent event;

    event.key = (u8)((status >> NOTE_KEY_SHIFT) & NOTE_KEY_MASK);
    event.key3 = (u8)((status >> NOTE_KEY3_SHIFT) & NOTE_KEY_MASK);
    event.key12 = (u8)((status >> NOTE_KEY12_SHIFT) & NOTE_KEY_MASK);
    event.key48 = (u8)((status >> NOTE_KEY48_SHIFT) & NOTE_KEY_MASK);
    event.selected_bank = (u8)((status >> NOTE_SELECTED_BANK_SHIFT) & NOTE_SELECTED_BANK_MASK);
    event.power3_exp = 0U;
    event.power3_mant = 0U;
    event.power12_exp = 0U;
    event.power12_mant = 0U;
    event.power48_exp = 0U;
    event.power48_mant = 0U;

    return event;
}

static void DecodePowerStatus(NoteEvent *event, u32 page1_status, u32 page2_status)
{
    event->power3_exp = (u8)((page1_status >> 24U) & NOTE_POWER_EXP_MASK);
    event->power3_mant = (u8)((page1_status >> 16U) & NOTE_POWER_MANT_MASK);
    event->power12_exp = (u8)((page1_status >> 9U) & NOTE_POWER_EXP_MASK);
    event->power12_mant = (u8)((page1_status >> 1U) & NOTE_POWER_MANT_MASK);
    event->power48_exp = (u8)((page2_status >> 24U) & NOTE_POWER_EXP_MASK);
    event->power48_mant = (u8)((page2_status >> 16U) & NOTE_POWER_MANT_MASK);
}

static void QueueNoteEvent(NoteEvent event)
{
    u8 next_head = (u8)((QueueHead + 1U) % NOTE_QUEUE_LENGTH);

    if (next_head == QueueTail) {
        DroppedEvents++;
        return;
    }

    NoteQueue[QueueHead] = event;
    QueueHead = next_head;
}

static int DequeueNoteEvent(NoteEvent *event)
{
    if (QueueTail == QueueHead) {
        return 0;
    }

    *event = NoteQueue[QueueTail];
    QueueTail = (u8)((QueueTail + 1U) % NOTE_QUEUE_LENGTH);
    return 1;
}

static void ClearNoteQueue(void)
{
    QueueHead = 0U;
    QueueTail = 0U;
}

static void DisarmNoteOutput(void)
{
    NoteOutputArmed = 0U;
}

static void ArmSingleNoteOutput(void)
{
    NoteOutputArmed = 1U;
}

static int CapturePendingNote(XGpio *gpio)
{
    u32 status;
    u32 power_page1;
    u32 power_page2;
    SelectDebugPage(0U);
    status = XGpio_DiscreteRead(gpio, NOTE_GPIO_STATUS_CHANNEL);
    NoteEvent event = DecodeNoteStatus(status);

    if ((status & NOTE_PENDING_MASK) == 0U) {
        return 0;
    }

    SelectDebugPage(1U);
    power_page1 = XGpio_DiscreteRead(gpio, NOTE_GPIO_STATUS_CHANNEL);
    SelectDebugPage(2U);
    power_page2 = XGpio_DiscreteRead(gpio, NOTE_GPIO_STATUS_CHANNEL);
    SelectDebugPage(0U);
    DecodePowerStatus(&event, power_page1, power_page2);

    if ((NoteOutputArmed != 0U) && (event.key >= 1U) && (event.key <= 88U)) {
        QueueNoteEvent(event);
        LastLevelKey = event.key;
        DisarmNoteOutput();
    }

    PulseNoteClear();
    return 1;
}

static void NoteInterruptHandler(void *CallbackRef)
{
    (void)CapturePendingNote((XGpio *)CallbackRef);
}

static void PollNoteLatch(void)
{
    (void)CapturePendingNote(&NoteGpio);
}

static int SetupGpio(void)
{
    int status = XGpio_Initialize(&NoteGpio, NOTE_GPIO_DEVICE_ID);
    if (status != XST_SUCCESS) {
        return status;
    }

    XGpio_SetDataDirection(&NoteGpio, NOTE_GPIO_STATUS_CHANNEL, 0xFFFFFFFFU);
    XGpio_SetDataDirection(&NoteGpio, NOTE_GPIO_CLEAR_CHANNEL, 0x00U);
    SelectDebugPage(0U);
    PulseNoteClear();
    return XST_SUCCESS;
}

static int SetupInterrupts(void)
{
    int status;
    XScuGic_Config *config;

    config = XScuGic_LookupConfig(NOTE_GIC_DEVICE_ID);
    if (config == NULL) {
        return XST_FAILURE;
    }

    status = XScuGic_CfgInitialize(&InterruptController, config, config->CpuBaseAddress);
    if (status != XST_SUCCESS) {
        return status;
    }

    XScuGic_SetPriorityTriggerType(&InterruptController, NOTE_IRQ_ID, 0xA0U, 0x1U);

    status = XScuGic_Connect(
        &InterruptController,
        NOTE_IRQ_ID,
        (Xil_ExceptionHandler)NoteInterruptHandler,
        &NoteGpio
    );
    if (status != XST_SUCCESS) {
        return status;
    }

    XScuGic_Enable(&InterruptController, NOTE_IRQ_ID);

    Xil_ExceptionInit();
    Xil_ExceptionRegisterHandler(
        XIL_EXCEPTION_ID_INT,
        (Xil_ExceptionHandler)XScuGic_InterruptHandler,
        &InterruptController
    );
    Xil_ExceptionEnable();

    return XST_SUCCESS;
}

static void SamplePlayerDisable(void)
{
    Xil_Out32(SAMPLE_PLAYER_BASEADDR + SAMPLE_PLAYER_CONTROL, 0U);
}

static void SamplePlayerRestartAndEnable(void)
{
    Xil_Out32(SAMPLE_PLAYER_BASEADDR + SAMPLE_PLAYER_CONTROL, SAMPLE_CONTROL_RESTART);
    usleep(1000U);
    Xil_Out32(SAMPLE_PLAYER_BASEADDR + SAMPLE_PLAYER_CONTROL, SAMPLE_CONTROL_ENABLE);
}

static int SetupSamplePlayer(void)
{
    SamplePlayerDisable();
    Xil_Out32(SAMPLE_PLAYER_BASEADDR + SAMPLE_PLAYER_CONTROL, SAMPLE_CONTROL_RESTART);
    usleep(1000U);
    SamplePlayerDisable();

    if (Xil_In32(SAMPLE_PLAYER_BASEADDR + SAMPLE_PLAYER_COUNT) != SAMPLE_BUFFER_WORDS) {
        return XST_FAILURE;
    }

    return XST_SUCCESS;
}

static int HexValue(char c, u32 *value)
{
    if ((c >= '0') && (c <= '9')) {
        *value = (u32)(c - '0');
        return 1;
    }
    if ((c >= 'A') && (c <= 'F')) {
        *value = (u32)(c - 'A' + 10);
        return 1;
    }
    if ((c >= 'a') && (c <= 'f')) {
        *value = (u32)(c - 'a' + 10);
        return 1;
    }
    return 0;
}

static int ParseHexDigits(const char **cursor, u32 digits, u32 *value)
{
    u32 parsed = 0U;
    u32 nibble;
    const char *text = *cursor;

    for (u32 index = 0U; index < digits; index++) {
        if (HexValue(text[index], &nibble) == 0) {
            return 0;
        }
        parsed = (parsed << 4) | nibble;
    }

    *cursor = text + digits;
    *value = parsed;
    return 1;
}

static int ParseDecimal(const char **cursor, u32 *value)
{
    u32 parsed = 0U;
    u32 digit_count = 0U;
    const char *text = *cursor;

    while ((*text >= '0') && (*text <= '9')) {
        parsed = (parsed * 10U) + (u32)(*text - '0');
        text++;
        digit_count++;
    }

    if (digit_count == 0U) {
        return 0;
    }

    *cursor = text;
    *value = parsed;
    return 1;
}

static int ParseLoadCommand(const char *line, u32 *sample_count, u32 *expected_checksum)
{
    const char *cursor = line;

    if ((cursor[0] != 'L') || (cursor[1] != 'O') || (cursor[2] != 'A') ||
        (cursor[3] != 'D') || (cursor[4] != ',')) {
        return 0;
    }
    cursor += 5;

    if (ParseDecimal(&cursor, sample_count) == 0) {
        return 0;
    }
    if (*cursor != ',') {
        return 0;
    }
    cursor++;

    if (ParseHexDigits(&cursor, 8U, expected_checksum) == 0) {
        return 0;
    }

    return *cursor == '\0';
}

static int ParseSampleWord(const char *line, u32 *sample_word)
{
    const char *cursor = line;

    if (ParseHexDigits(&cursor, 6U, sample_word) == 0) {
        return 0;
    }

    if (*cursor != '\0') {
        return 0;
    }

    *sample_word &= SAMPLE_WORD_MASK;
    return 1;
}

static int ReadUartLineBlocking(char *line, u32 line_capacity)
{
    u32 length = 0U;
    u32 idle_polls = 0U;
    u8 byte;

    while (idle_polls < UART_LINE_TIMEOUT_POLLS) {
        if (XUartPs_IsReceiveData(STDIN_BASEADDRESS) != 0U) {
            byte = XUartPs_RecvByte(STDIN_BASEADDRESS);
            idle_polls = 0U;

            if (byte == '\r') {
                continue;
            }

            if (byte == '\n') {
                line[length] = '\0';
                return 1;
            }

            if (length + 1U >= line_capacity) {
                return 0;
            }

            line[length] = (char)byte;
            length++;
        } else {
            idle_polls++;
            usleep(UART_POLL_DELAY_US);
        }
    }

    return 0;
}

static void LoadSamplesFromUart(u32 sample_count, u32 expected_checksum)
{
    char sample_line[SAMPLE_LINE_LENGTH];
    u32 checksum = 0U;
    u32 sample_word;

    if (sample_count != SAMPLE_BUFFER_WORDS) {
        xil_printf("ERROR,load,count\r\n");
        return;
    }

    SamplePlayerDisable();
    PulseNoteClear();
    ClearNoteQueue();
    DisarmNoteOutput();
    LastLevelKey = 0U;

    for (u32 index = 0U; index < SAMPLE_BUFFER_WORDS; index++) {
        if (ReadUartLineBlocking(sample_line, SAMPLE_LINE_LENGTH) == 0) {
            xil_printf("ERROR,load,timeout,%lu\r\n", (unsigned long)index);
            SamplePlayerDisable();
            PulseNoteClear();
            ClearNoteQueue();
            DisarmNoteOutput();
            return;
        }

        if (ParseSampleWord(sample_line, &sample_word) == 0) {
            xil_printf("ERROR,load,bad_sample,%lu,%s\r\n", (unsigned long)index, sample_line);
            SamplePlayerDisable();
            PulseNoteClear();
            ClearNoteQueue();
            DisarmNoteOutput();
            return;
        }

        Xil_Out32(
            SAMPLE_PLAYER_BASEADDR + SAMPLE_PLAYER_DATA + (index * sizeof(u32)),
            sample_word
        );
        checksum += sample_word;
    }

    if (checksum != expected_checksum) {
        xil_printf(
            "ERROR,load,checksum,%08lx,%08lx\r\n",
            (unsigned long)checksum,
            (unsigned long)expected_checksum
        );
        SamplePlayerDisable();
        PulseNoteClear();
        ClearNoteQueue();
        DisarmNoteOutput();
        return;
    }

    PulseNoteClear();
    ClearNoteQueue();
    ArmSingleNoteOutput();
    SamplePlayerRestartAndEnable();
    xil_printf("LOADED,%lu,%08lx\r\n", (unsigned long)SAMPLE_BUFFER_WORDS, (unsigned long)checksum);
}

static void ProcessUartCommand(const char *line)
{
    u32 sample_count;
    u32 expected_checksum;

    if (ParseLoadCommand(line, &sample_count, &expected_checksum) != 0) {
        LoadSamplesFromUart(sample_count, expected_checksum);
    }
}

static void PollUartCommands(void)
{
    u8 byte;

    while (XUartPs_IsReceiveData(STDIN_BASEADDRESS) != 0U) {
        byte = XUartPs_RecvByte(STDIN_BASEADDRESS);

        if (byte == '\r') {
            continue;
        }

        if (byte == '\n') {
            CommandLine[CommandLength] = '\0';
            if (CommandLength > 0U) {
                ProcessUartCommand(CommandLine);
            }
            CommandLength = 0U;
            return;
        }

        if (CommandLength + 1U >= UART_COMMAND_LINE_LENGTH) {
            CommandLength = 0U;
            xil_printf("ERROR,command,line_too_long\r\n");
            return;
        }

        CommandLine[CommandLength] = (char)byte;
        CommandLength++;
    }
}

static void PrintNoteCsv(u8 key)
{
    u32 freq = NoteFreqCentiHz[key];
    xil_printf(
        "%u,%s,%lu.%02lu\r\n",
        key,
        NoteNames[key],
        (unsigned long)(freq / 100U),
        (unsigned long)(freq % 100U)
    );
}

static const char *SelectedBankName(u8 selected_bank)
{
    switch (selected_bank) {
    case 0U:
        return "3k";
    case 1U:
        return "12k";
    case 2U:
        return "48k";
    default:
        return "unknown";
    }
}

static void PrintNoteDebug(NoteEvent event)
{
    xil_printf(
        "DEBUG,final=%u,bank3k=%u,bank12k=%u,bank48k=%u,selected=%s,p3=%u:%02x,p12=%u:%02x,p48=%u:%02x\r\n",
        event.key,
        event.key3,
        event.key12,
        event.key48,
        SelectedBankName(event.selected_bank),
        event.power3_exp,
        event.power3_mant,
        event.power12_exp,
        event.power12_mant,
        event.power48_exp,
        event.power48_mant
    );
}

int main(void)
{
    int status;
    NoteEvent event;

    status = SetupGpio();
    if (status != XST_SUCCESS) {
        xil_printf("ERROR,gpio_init,%d\r\n", status);
        return XST_FAILURE;
    }

    status = SetupInterrupts();
    if (status != XST_SUCCESS) {
        xil_printf("ERROR,interrupt_init,%d\r\n", status);
        return XST_FAILURE;
    }

    status = SetupSamplePlayer();
    if (status != XST_SUCCESS) {
        xil_printf("ERROR,sample_player_init,%d\r\n", status);
        return XST_FAILURE;
    }

    xil_printf(
        "READY,note_uart_app,115200,gpio=0x%08lx,irq=%lu,sample=0x%08lx\r\n",
        (unsigned long)NOTE_GPIO_DEVICE_ID,
        (unsigned long)NOTE_IRQ_ID,
        (unsigned long)SAMPLE_PLAYER_BASEADDR
    );

    while (1) {
        PollUartCommands();
        PollNoteLatch();

        while (DequeueNoteEvent(&event) != 0) {
            PrintNoteDebug(event);
            PrintNoteCsv(event.key);
        }

        usleep(NOTE_POLL_DELAY_US);
    }

    return XST_SUCCESS;
}
