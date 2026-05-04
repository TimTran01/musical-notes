#include "sleep.h"
#include "xgpio.h"
#include "xil_exception.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xscugic.h"
#include "xstatus.h"

#define NOTE_GPIO_STATUS_CHANNEL 1U
#define NOTE_GPIO_CLEAR_CHANNEL  2U
#define NOTE_PENDING_MASK        0x80U
#define NOTE_KEY_MASK            0x7FU
#define NOTE_QUEUE_LENGTH        16U
#define NOTE_POLL_DELAY_US       10000U

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

static XGpio NoteGpio;
static XScuGic InterruptController;

static volatile u8 NoteQueue[NOTE_QUEUE_LENGTH];
static volatile u8 QueueHead = 0U;
static volatile u8 QueueTail = 0U;
static volatile u32 DroppedEvents = 0U;

static u8 LastLevelKey = 0U;

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
    XGpio_DiscreteWrite(&NoteGpio, NOTE_GPIO_CLEAR_CHANNEL, 1U);
    XGpio_DiscreteWrite(&NoteGpio, NOTE_GPIO_CLEAR_CHANNEL, 0U);
}

static void QueueNoteKey(u8 key)
{
    u8 next_head = (u8)((QueueHead + 1U) % NOTE_QUEUE_LENGTH);

    if (next_head == QueueTail) {
        DroppedEvents++;
        return;
    }

    NoteQueue[QueueHead] = key;
    QueueHead = next_head;
}

static int DequeueNoteKey(u8 *key)
{
    if (QueueTail == QueueHead) {
        return 0;
    }

    *key = NoteQueue[QueueTail];
    QueueTail = (u8)((QueueTail + 1U) % NOTE_QUEUE_LENGTH);
    return 1;
}

static int CapturePendingNote(XGpio *gpio)
{
    u32 status = XGpio_DiscreteRead(gpio, NOTE_GPIO_STATUS_CHANNEL);
    u8 key = (u8)(status & NOTE_KEY_MASK);

    if ((status & NOTE_PENDING_MASK) == 0U) {
        return 0;
    }

    if ((key >= 1U) && (key <= 88U)) {
        QueueNoteKey(key);
        LastLevelKey = key;
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

static void PollKeyLevelFallback(void)
{
    u32 status = XGpio_DiscreteRead(&NoteGpio, NOTE_GPIO_STATUS_CHANNEL);
    u8 key = (u8)(status & NOTE_KEY_MASK);

    if ((status & NOTE_PENDING_MASK) != 0U) {
        return;
    }

    if ((key < 1U) || (key > 88U)) {
        return;
    }

    if (key != LastLevelKey) {
        QueueNoteKey(key);
        LastLevelKey = key;
    }
}

static int SetupGpio(void)
{
    int status = XGpio_Initialize(&NoteGpio, NOTE_GPIO_DEVICE_ID);
    if (status != XST_SUCCESS) {
        return status;
    }

    XGpio_SetDataDirection(&NoteGpio, NOTE_GPIO_STATUS_CHANNEL, 0xFFU);
    XGpio_SetDataDirection(&NoteGpio, NOTE_GPIO_CLEAR_CHANNEL, 0x00U);
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

int main(void)
{
    int status;
    u8 key;

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

    xil_printf(
        "READY,note_uart_app,115200,gpio=0x%08lx,irq=%lu\r\n",
        (unsigned long)NOTE_GPIO_DEVICE_ID,
        (unsigned long)NOTE_IRQ_ID
    );

    while (1) {
        PollNoteLatch();
        PollKeyLevelFallback();

        while (DequeueNoteKey(&key) != 0) {
            PrintNoteCsv(key);
        }

        usleep(NOTE_POLL_DELAY_US);
    }

    return XST_SUCCESS;
}
