/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * EEE3096S 2026 - Practical 1B
  * Tasks 2 and 3: fast integer square root, TIM16 timing, optimisation flags
  *
 Hazel Mpakati and Tinashe Masvore
  * Date     : 2026-08-29
  *
  * Board pins used
  *   PC13 : scope pulse. Driven LOW for the timed section, HIGH otherwise.
  *          Broken out on Header P1.
  *   PB1  : pass or fail indicator. User LED 1. ON means all ten golden
  *          values matched.
  *
  * Search for TODO. Every TODO is a piece of work you have to complete.
  * Do not delete the USER CODE markers. STM32CubeIDE overwrites everything
  * outside them whenever you regenerate from the .ioc file.
  ******************************************************************************
  */
/* USER CODE END Header */

/* Includes ------------------------------------------------------------------*/
#include "main.h"
/* USER CODE BEGIN Includes */
#include <stdint.h>
/* USER CODE END Includes */

/* USER CODE BEGIN PD */
#define PULSE_PIN    13u          /* PC13 */
#define LED_PIN      1u           /* PB1  */

#define TEST_INPUT   987654321u   /* the input named in the Task 2 question */
#define LONG_RUN_N   20000u       /* calls in the wrap-around run           */
/* USER CODE END PD */

/* USER CODE BEGIN PV */

/* The ten inputs from Task 1. Do not change these. */
static const uint32_t golden_inputs[10] = {
    0u, 1u, 15u, 16u, 4095u, 65535u,
    123456789u, 987654321u, 4294836225u, 4294967295u
};

/*
 * TODO 1
 * Fill this array with the ten outputs produced by YOUR Task 1 golden
 * measure. Copy them from your own PC run, not from a friend and not from
 * the practical sheet. The firmware self-test below compares against these.
 */
static const uint32_t golden_outputs[10] = {
    0u, 1u, 3u, 4u, 63u, 255u,
    11111u, 31426u, 65535u, 65535u
};

/*
 * Results. Keep these volatile so the optimiser leaves them alone at -O1
 * and above. Read them in the STM32CubeIDE Live Expressions view.
 */
volatile uint8_t  pass_all          = 0u;   /* 1 means all ten matched      */
volatile uint32_t single_call_span  = 0u;   /* timer counts, one call       */
volatile uint32_t long_run_span     = 0u;   /* timer counts, LONG_RUN_N     */
volatile float    mean_us_per_call  = 0.0f; /* long run divided by N        */

/* Sink for the return value. Stops the optimiser deleting the call. */
static volatile uint32_t sink = 0u;

/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/
void SystemClock_Config(void);

/* USER CODE BEGIN PFP */
static void     gpio_init(void);
static void     timing_timer_init(void);
static uint32_t isqrt(uint32_t x);
static uint32_t time_one_call(uint32_t x);
static uint32_t time_n_calls(uint32_t x, uint32_t n);
/* USER CODE END PFP */

/* USER CODE BEGIN 0 */

/* ---------------------------------------------------------------------------
 * Hardware initialisation
 * ------------------------------------------------------------------------ */
static void gpio_init(void)
{
    /*
     * TODO 2
     * Enable the peripheral clock for GPIOC and GPIOB.
     *
     * Look up the correct RCC enable register in RM0091 Section 6, Reset
     * and Clock Control, and name the register in your report.
     *
     * RCC->???ENR |= ... ;
     */
    RCC->AHBENR |= RCC_AHBENR_GPIOBEN | RCC_AHBENR_GPIOCEN;

    /*
     * TODO 3
     * Put PC13 and PB1 into general purpose output mode.
     * MODER holds two bits per pin. Clear both bits first, then set the
     * output pattern. Leave every other pin untouched.
     */

    //PC13
    GPIOC->MODER &= ~(3UL << (PULSE_PIN * 2u)); //clear
    GPIOC->MODER |=  (1UL << (PULSE_PIN * 2u)); //set

    //PB1
    GPIOB->MODER &= ~(3UL << (LED_PIN * 2u));
    GPIOB->MODER |=  (1UL << (LED_PIN * 2u));

    /*
     * TODO 4
     * Set the idle states: PC13 HIGH (pulse is active low) and PB1 LOW
     * (LED off until the self-test passes).
     * BSRR sets a pin. BRR clears a pin.
     */
    GPIOC->BSRR = (1UL << PULSE_PIN);
    GPIOB->BRR  = (1UL << LED_PIN);
}

static void timing_timer_init(void)
{
    /*
     * TODO 5
     * Enable the TIM16 peripheral clock. TIM16 and the GPIO ports sit on
     * different buses on this device. Name both buses in your report.
     */
     RCC->APB2ENR |= RCC_APB2ENR_TIM16EN;

    /*
     * TODO 6
     * Set the prescaler so one timer count equals a time you choose and
     * state. The division factor is PSC + 1, so:
     *
     *   counter clock = timer clock / (PSC + 1)
     *
     * Work out the timer clock from the path HSI -> AHB prescaler ->
     * APB prescaler -> TIM16. Write the full path and every divider into
     * your report before you pick the number.
     *
     * TIM16->PSC = ??? ;
     */
    TIM16->PSC = 7u;

    /*
     * TODO 7
     * Set ARR for a free running 16-bit counter, force the prescaler to
     * load with an update event, then enable the counter.
     */
    TIM16->ARR = 0xFFFFu;
    TIM16->EGR = TIM_EGR_UG;
    TIM16->CR1 |= TIM_CR1_CEN;
}

/* ---------------------------------------------------------------------------
 * Task 2 core algorithm
 * ------------------------------------------------------------------------ */

/*
 * Helper. Returns non-zero when mid * mid is at or below x.
 *
 * Keep this as a separate function. Task 3 asks you to find one
 * optimisation transformation in the disassembly, and the treatment of
 * this helper at -O2 is the easiest one to spot and name.
 *
 * Note: mid * mid overflows 32 bits for large mid. Promote before you
 * multiply.
 */
static inline uint32_t square_le(uint32_t mid, uint32_t x)
{
    /* TODO 8: return the comparison result. */
    return ((uint64_t)mid * mid) <= x;
}

/*
 * Integer square root. Returns the largest r with r * r <= x, for every
 * x from 0 to 4294967295.
 */
static uint32_t isqrt(uint32_t x)
{
    /*
     * TODO 9
     * Implement a fast integer square root. A binary search over the
     * answer range works well and is simple to reason about.
     *
     */
    uint32_t lo = 0u;
    uint32_t hi = 65535u;
    uint32_t answer = 0u;

    while (lo <= hi)
    {
        uint32_t mid = lo + (hi - lo) / 2u;

        if (square_le(mid, x))
        {
            answer = mid;
            lo = mid + 1u;
        }
        else
        {
            if (mid == 0u)
            {
                break;
            }
            hi = mid - 1u;
        }
    }

    return answer;
}

/* ---------------------------------------------------------------------------
 * Timing harness
 * ------------------------------------------------------------------------ */

/*
 * Times one call.
 * Drives PC13 LOW for the timed window so the scope pulse and the counter
 * span cover the same code.
 * Returns the elapsed counter span.
 */
static uint32_t time_one_call(uint32_t x)
{
    uint16_t a = 0u;
    uint16_t b = 0u;

    GPIOC->BRR = (1UL << PULSE_PIN);   /* PC13 low: pulse starts */

    /* TODO 10: capture the counter into a. Which register holds the count? */
    a = (uint16_t)TIM16->CNT;

    sink = isqrt(x);                   /* the code under test */

    /* TODO 11: capture the counter into b. */
    b = (uint16_t)TIM16->CNT;

    GPIOC->BSRR = (1UL << PULSE_PIN);  /* PC13 high: pulse ends */

    /*
     * TODO 12
     * Return the elapsed span. The counter wraps at its top value during
     * long runs, so a plain b minus a is wrong once the counter rolls over.
     * Work out an expression correct across a wrap and explain it in your
     * report. Test your reasoning on a = 65500, b = 20.
     */
    return (uint32_t)((uint16_t)(b - a));
}

/*
 * Times n calls back to back so the counter crosses its overflow more
 * than once. Same arithmetic as the single call version.
 */
static uint32_t time_n_calls(uint32_t x, uint32_t n)
{
    uint16_t a = 0u;
    uint16_t b = 0u;
    uint32_t overflows = 0u;

    GPIOC->BRR = (1UL << PULSE_PIN);

    /* TODO 13: capture the counter into a. */
    a = (uint16_t)TIM16->CNT;

    for (uint32_t i = 0u; i < n; i++)
    {
        sink = isqrt(x);

        /* Check whether TIM16 overflowed */
        if (TIM16->SR & TIM_SR_UIF)
        {
            TIM16->SR &= ~TIM_SR_UIF;
            overflows++;
        }
    }

    /* TODO 14: capture the counter into b. */
    b = (uint16_t)TIM16->CNT;

    GPIOC->BSRR = (1UL << PULSE_PIN);

    /*
     * TODO 15
     * Return the elapsed span using the same wrap-safe expression.
     *
     * Careful: a 16-bit counter measures a limited window without
     * ambiguity. Work out that window from your prescaler, then pick n so
     * the total run stays inside a single unambiguous window, or track the
     * overflows yourself. State your choice in the report.
     */
    return (overflows * 65536u) + (uint32_t)((uint16_t)(b - a));
}

/* USER CODE END 0 */

/**
  * @brief  The application entry point.
  */
int main(void)
{
  /* MCU Configuration -------------------------------------------------------*/
  HAL_Init();
  SystemClock_Config();

  /* USER CODE BEGIN 2 */
  gpio_init();
  timing_timer_init();

  /* Self-test against the ten golden values from Task 1 */
  pass_all = 1u;
  for (int i = 0; i < 10; i++)
  {
      if (isqrt(golden_inputs[i]) != golden_outputs[i])
      {
          pass_all = 0u;
          break;
      }
  }

  /*
   * TODO 16
   * Drive PB1 from pass_all. LED on for a pass, off for a fail.
   * The demonstrator checks this LED before anything else.
   */
  if (pass_all)
  {
      GPIOB->BSRR = (1UL << LED_PIN);   /* LED ON */
  }
  else
  {
      GPIOB->BRR = (1UL << LED_PIN);    /* LED OFF */
  }

  /* USER CODE END 2 */

  /* Infinite loop */
  while (1)
  {
    /* USER CODE BEGIN 3 */

    /* Task 2 and Task 3: single call measurement */
    // single_call_span = time_one_call(TEST_INPUT);

    /*
     * TODO 17
     * Task 2 wrap case: run the long measurement, then work out the mean
     * time per call and confirm it agrees with the single call figure.
     *
     * Comment this out while you place the scope cursors on the single
     * call pulse. Two pulses of very different widths on one pin make the
     * scope trigger jump.
     */
    long_run_span = time_n_calls(TEST_INPUT, LONG_RUN_N);
    mean_us_per_call = (float)long_run_span / (float)LONG_RUN_N;

    /* Gap between measurements so the scope has a clean single pulse */
    for (volatile int d = 0; d < 100000; d++)
    {
    }
    /* USER CODE END 3 */
  }
}

/**
  * @brief System Clock Configuration
  * @retval None
  */
void SystemClock_Config(void)
{
  RCC_OscInitTypeDef RCC_OscInitStruct = {0};
  RCC_ClkInitTypeDef RCC_ClkInitStruct = {0};

  RCC_OscInitStruct.OscillatorType = RCC_OSCILLATORTYPE_HSI;
  RCC_OscInitStruct.HSIState = RCC_HSI_ON;
  RCC_OscInitStruct.HSICalibrationValue = RCC_HSICALIBRATION_DEFAULT;
  RCC_OscInitStruct.PLL.PLLState = RCC_PLL_NONE;
  if (HAL_RCC_OscConfig(&RCC_OscInitStruct) != HAL_OK)
  {
    Error_Handler();
  }

  RCC_ClkInitStruct.ClockType = RCC_CLOCKTYPE_HCLK | RCC_CLOCKTYPE_SYSCLK
                              | RCC_CLOCKTYPE_PCLK1;
  RCC_ClkInitStruct.SYSCLKSource = RCC_SYSCLKSOURCE_HSI;
  RCC_ClkInitStruct.AHBCLKDivider = RCC_SYSCLK_DIV1;
  RCC_ClkInitStruct.APB1CLKDivider = RCC_HCLK_DIV1;

  if (HAL_RCC_ClockConfig(&RCC_ClkInitStruct, FLASH_LATENCY_0) != HAL_OK)
  {
    Error_Handler();
  }
}

/**
  * @brief  This function is executed in case of error occurrence.
  */
void Error_Handler(void)
{
  __disable_irq();
  while (1)
  {
  }
}

#ifdef  USE_FULL_ASSERT
void assert_failed(uint8_t *file, uint32_t line)
{
}
#endif /* USE_FULL_ASSERT */
