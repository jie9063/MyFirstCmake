/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file           : main.c
  * @brief          : Main program body
  ******************************************************************************
  * @attention
  *
  * Copyright (c) 2026 STMicroelectronics.
  * All rights reserved.
  *
  * This software is licensed under terms that can be found in the LICENSE file
  * in the root directory of this software component.
  * If no LICENSE file comes with this software, it is provided AS-IS.
  *
  ******************************************************************************
  */
/* USER CODE END Header */
/* Includes ------------------------------------------------------------------*/
#include "main.h"

/* Private includes ----------------------------------------------------------*/
/* USER CODE BEGIN Includes */
#include <stdio.h>
#include <string.h>

/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/
/* USER CODE BEGIN PTD */
typedef struct
{
  uint8_t year;
  uint8_t month;
  uint8_t day;
  uint8_t hour;
  uint8_t minute;
  uint8_t second;
} ds1307_time_t;

/* USER CODE END PTD */

/* Private define ------------------------------------------------------------*/
/* USER CODE BEGIN PD */
#define B1_DEBOUNCE_MS        50U
#define ADC_SAMPLES            32U
#define ADC_MAX_COUNTS         4095U
#define VREF_MV                3300U
#define RREF_OHM               10000U
/* USER CODE END PD */

/* Private macro -------------------------------------------------------------*/
/* USER CODE BEGIN PM */

/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/
ADC_HandleTypeDef hadc1;

I2C_HandleTypeDef hi2c1;

RTC_HandleTypeDef hrtc;

/* USER CODE BEGIN PV */
/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/
void SystemClock_Config(void);
static void MX_GPIO_Init(void);
static void MX_I2C1_Init(void);
static void MX_RTC_Init(void);
static void MX_ADC1_Init(void);
/* USER CODE BEGIN PFP */

/* USER CODE END PFP */

/* Private user code ---------------------------------------------------------*/
/* USER CODE BEGIN 0 */
#define LCD_COLS              16U
#define LCD_BACKLIGHT         0x08U
#define LCD_ENABLE            0x04U
#define LCD_RS                0x01U
#define DS1307_ADDR_8BIT      (0x68U << 1)
#define I2C_DIAG_RETRY        3U
#define I2C_DIAG_READY_TO_MS  20U
#define DS1307_FORCE_SYNC_AT_BOOT 0U

static uint8_t lcd_addr_8bit = 0U;
static uint32_t last_update_ms = 0U;
static uint32_t b1_last_event_ms = 0U;
static uint8_t i2c_found_count = 0U;
static uint8_t has_lcd_27 = 0U;
static uint8_t has_lcd_3f = 0U;
static uint8_t has_rtc_68 = 0U;
static uint8_t has_eeprom_50 = 0U;
static uint8_t lcd_ready = 0U;
static volatile uint8_t force_refresh_request = 0U;
static volatile uint8_t zero_time_request = 0U;
volatile uint32_t i2c_last_error = 0U;
volatile uint8_t i2c_last_addr_7bit = 0U;
volatile uint8_t i2c_last_stage = 0U;

static uint8_t bcd_to_bin(uint8_t bcd)
{
  return (uint8_t)(((bcd >> 4) * 10U) + (bcd & 0x0FU));
}

static uint8_t bin_to_bcd(uint8_t bin)
{
  return (uint8_t)(((bin / 10U) << 4) | (bin % 10U));
}

static uint8_t month_str_to_num(const char *m)
{
  if (strncmp(m, "Jan", 3) == 0) return 1U;
  if (strncmp(m, "Feb", 3) == 0) return 2U;
  if (strncmp(m, "Mar", 3) == 0) return 3U;
  if (strncmp(m, "Apr", 3) == 0) return 4U;
  if (strncmp(m, "May", 3) == 0) return 5U;
  if (strncmp(m, "Jun", 3) == 0) return 6U;
  if (strncmp(m, "Jul", 3) == 0) return 7U;
  if (strncmp(m, "Aug", 3) == 0) return 8U;
  if (strncmp(m, "Sep", 3) == 0) return 9U;
  if (strncmp(m, "Oct", 3) == 0) return 10U;
  if (strncmp(m, "Nov", 3) == 0) return 11U;
  if (strncmp(m, "Dec", 3) == 0) return 12U;
  return 1U;
}

static HAL_StatusTypeDef ds1307_set_from_build_time(void)
{
  /* Reg 0x00..0x06: sec,min,hour,weekday,date,month,year */
  uint8_t payload[8];
  const char *d = __DATE__; /* "Mmm dd yyyy" */
  const char *t = __TIME__; /* "hh:mm:ss" */
  uint8_t month = month_str_to_num(d);
  uint8_t day = (uint8_t)(((d[4] == ' ') ? 0 : (d[4] - '0')) * 10 + (d[5] - '0'));
  uint8_t year = (uint8_t)(((d[9] - '0') * 10) + (d[10] - '0'));
  uint8_t hour = (uint8_t)(((t[0] - '0') * 10) + (t[1] - '0'));
  uint8_t minute = (uint8_t)(((t[3] - '0') * 10) + (t[4] - '0'));
  uint8_t second = (uint8_t)(((t[6] - '0') * 10) + (t[7] - '0'));

  payload[0] = 0x00U;
  payload[1] = bin_to_bcd(second); /* CH=0, second */
  payload[2] = bin_to_bcd(minute); /* minute */
  payload[3] = bin_to_bcd(hour);   /* hour (24h) */
  payload[4] = bin_to_bcd(1U);   /* weekday=1 */
  payload[5] = bin_to_bcd(day);   /* date */
  payload[6] = bin_to_bcd(month); /* month */
  payload[7] = bin_to_bcd(year);  /* year */

  if (HAL_I2C_Master_Transmit(&hi2c1, DS1307_ADDR_8BIT, payload, sizeof(payload), 100U) != HAL_OK)
  {
    i2c_last_error = hi2c1.ErrorCode;
    i2c_last_addr_7bit = 0x68U;
    i2c_last_stage = 3U;
    return HAL_ERROR;
  }

  return HAL_OK;
}

static HAL_StatusTypeDef ds1307_set_time_zero(void)
{
  /* Reg 0x00..0x02: sec,min,hour (24h). Keep CH=0 to run oscillator. */
  uint8_t payload[4];
  payload[0] = 0x00U;
  payload[1] = 0x00U;
  payload[2] = 0x00U;
  payload[3] = 0x00U;

  if (HAL_I2C_Master_Transmit(&hi2c1, DS1307_ADDR_8BIT, payload, sizeof(payload), 100U) != HAL_OK)
  {
    i2c_last_error = hi2c1.ErrorCode;
    i2c_last_addr_7bit = 0x68U;
    i2c_last_stage = 7U;
    return HAL_ERROR;
  }

  return HAL_OK;
}

static HAL_StatusTypeDef lcd_write(uint8_t data)
{
  return HAL_I2C_Master_Transmit(&hi2c1, lcd_addr_8bit, &data, 1U, HAL_MAX_DELAY);
}

static HAL_StatusTypeDef i2c_is_ready_retry(uint8_t addr_7bit)
{
  uint32_t try_idx;
  HAL_StatusTypeDef st = HAL_ERROR;

  for (try_idx = 0U; try_idx < I2C_DIAG_RETRY; try_idx++)
  {
    st = HAL_I2C_IsDeviceReady(&hi2c1, (uint16_t)(addr_7bit << 1), 2U, I2C_DIAG_READY_TO_MS);
    if (st == HAL_OK)
    {
      i2c_last_error = 0U;
      return HAL_OK;
    }
    i2c_last_error = hi2c1.ErrorCode;
    i2c_last_addr_7bit = addr_7bit;
  }

  return st;
}

static void lcd_pulse(uint8_t data)
{
  (void)lcd_write((uint8_t)(data | LCD_ENABLE | LCD_BACKLIGHT));
  HAL_Delay(1);
  (void)lcd_write((uint8_t)((data & (uint8_t)(~LCD_ENABLE)) | LCD_BACKLIGHT));
  HAL_Delay(1);
}

static void lcd_send4(uint8_t nibble_rs)
{
  uint8_t data = (uint8_t)(nibble_rs | LCD_BACKLIGHT);
  (void)lcd_write(data);
  lcd_pulse(data);
}

static void lcd_send(uint8_t value, uint8_t rs)
{
  lcd_send4((uint8_t)((value & 0xF0U) | rs));
  lcd_send4((uint8_t)(((value << 4) & 0xF0U) | rs));
}

static void lcd_cmd(uint8_t cmd)
{
  lcd_send(cmd, 0U);
}

static void lcd_data(uint8_t data)
{
  lcd_send(data, LCD_RS);
}

static HAL_StatusTypeDef lcd_detect_address(void)
{
  uint8_t a;
  for (a = 0x20U; a <= 0x3FU; a++)
  {
    if (i2c_is_ready_retry(a) == HAL_OK)
    {
      lcd_addr_8bit = (uint8_t)(a << 1);
      return HAL_OK;
    }
  }

  return HAL_ERROR;
}

static HAL_StatusTypeDef lcd_init(void)
{
  if (lcd_detect_address() != HAL_OK)
  {
    return HAL_ERROR;
  }

  HAL_Delay(50);
  lcd_send4(0x30U);
  HAL_Delay(5);
  lcd_send4(0x30U);
  HAL_Delay(1);
  lcd_send4(0x30U);
  HAL_Delay(1);
  lcd_send4(0x20U);
  HAL_Delay(1);

  lcd_cmd(0x28U);
  lcd_cmd(0x08U);
  lcd_cmd(0x01U);
  HAL_Delay(2);
  lcd_cmd(0x06U);
  lcd_cmd(0x0CU);
  return HAL_OK;
}

static void lcd_set_cursor(uint8_t row, uint8_t col)
{
  const uint8_t row_offset[] = {0x00U, 0x40U, 0x14U, 0x54U};
  lcd_cmd((uint8_t)(0x80U | (row_offset[row] + col)));
}

static void lcd_print_line(uint8_t row, const char *text)
{
  char line[LCD_COLS + 1];
  size_t len = strlen(text);
  size_t i;

  if (len > LCD_COLS)
  {
    len = LCD_COLS;
  }
  memset(line, ' ', LCD_COLS);
  memcpy(line, text, len);
  line[LCD_COLS] = '\0';

  lcd_set_cursor(row, 0U);
  for (i = 0U; i < LCD_COLS; i++)
  {
    lcd_data((uint8_t)line[i]);
  }
}

static HAL_StatusTypeDef ds1307_read(ds1307_time_t *t)
{
  uint8_t reg = 0x00U;
  uint8_t raw[7] = {0};

  if (HAL_I2C_Master_Transmit(&hi2c1, DS1307_ADDR_8BIT, &reg, 1U, 100U) != HAL_OK)
  {
    i2c_last_error = hi2c1.ErrorCode;
    i2c_last_addr_7bit = 0x68U;
    i2c_last_stage = 1U;
    return HAL_ERROR;
  }

  if (HAL_I2C_Master_Receive(&hi2c1, DS1307_ADDR_8BIT, raw, 7U, 100U) != HAL_OK)
  {
    i2c_last_error = hi2c1.ErrorCode;
    i2c_last_addr_7bit = 0x68U;
    i2c_last_stage = 2U;
    return HAL_ERROR;
  }

  if ((raw[0] & 0x80U) != 0U)
  {
    /* DS1307 CH bit = 1 means oscillator stopped. Re-initialize once. */
    if (ds1307_set_from_build_time() != HAL_OK)
    {
      return HAL_ERROR;
    }

    if (HAL_I2C_Master_Transmit(&hi2c1, DS1307_ADDR_8BIT, &reg, 1U, 100U) != HAL_OK)
    {
      i2c_last_error = hi2c1.ErrorCode;
      i2c_last_addr_7bit = 0x68U;
      i2c_last_stage = 4U;
      return HAL_ERROR;
    }
    if (HAL_I2C_Master_Receive(&hi2c1, DS1307_ADDR_8BIT, raw, 7U, 100U) != HAL_OK)
    {
      i2c_last_error = hi2c1.ErrorCode;
      i2c_last_addr_7bit = 0x68U;
      i2c_last_stage = 5U;
      return HAL_ERROR;
    }
    if ((raw[0] & 0x80U) != 0U)
    {
      i2c_last_stage = 6U;
      return HAL_ERROR;
    }
  }

  t->second = bcd_to_bin((uint8_t)(raw[0] & 0x7FU));
  t->minute = bcd_to_bin((uint8_t)(raw[1] & 0x7FU));
  t->hour = bcd_to_bin((uint8_t)(raw[2] & 0x3FU));
  t->day = bcd_to_bin((uint8_t)(raw[4] & 0x3FU));
  t->month = bcd_to_bin((uint8_t)(raw[5] & 0x1FU));
  t->year = bcd_to_bin(raw[6]);
  return HAL_OK;
}

static void i2c_scan_known(void)
{
  uint8_t a;
  i2c_found_count = 0U;
  has_lcd_27 = 0U;
  has_lcd_3f = 0U;
  has_rtc_68 = 0U;
  has_eeprom_50 = 0U;

  for (a = 0x08U; a <= 0x77U; a++)
  {
    if (i2c_is_ready_retry(a) == HAL_OK)
    {
      i2c_found_count++;
      if (a == 0x27U) has_lcd_27 = 1U;
      if (a == 0x3FU) has_lcd_3f = 1U;
      if (a == 0x68U) has_rtc_68 = 1U;
      if (a == 0x50U) has_eeprom_50 = 1U;
    }
  }
}

static HAL_StatusTypeDef adc_read_avg_u12(uint16_t *avg)
{
  uint32_t sum = 0U;
  uint32_t i;

  for (i = 0U; i < ADC_SAMPLES; i++)
  {
    if (HAL_ADC_Start(&hadc1) != HAL_OK) return HAL_ERROR;
    if (HAL_ADC_PollForConversion(&hadc1, 10U) != HAL_OK)
    {
      (void)HAL_ADC_Stop(&hadc1);
      return HAL_ERROR;
    }
    sum += HAL_ADC_GetValue(&hadc1);
    if (HAL_ADC_Stop(&hadc1) != HAL_OK) return HAL_ERROR;
  }

  *avg = (uint16_t)(sum / ADC_SAMPLES);
  return HAL_OK;
}

static uint8_t calc_rx_ohm_from_adc(uint16_t adc, uint32_t *rx_ohm, uint32_t *vout_mv)
{
  if (adc >= (ADC_MAX_COUNTS - 1U))
  {
    *vout_mv = VREF_MV;
    *rx_ohm = 0U;
    return 0U; /* over range / open */
  }

  *vout_mv = (VREF_MV * (uint32_t)adc) / ADC_MAX_COUNTS;
  *rx_ohm = (RREF_OHM * (uint32_t)adc) / (ADC_MAX_COUNTS - (uint32_t)adc);
  return 1U;
}

static void format_resistance(char *line, size_t n, uint32_t rx_ohm, uint8_t valid, uint32_t vout_mv)
{
  uint32_t v_int = vout_mv / 1000U;
  uint32_t v_frac2 = (vout_mv % 1000U) / 10U;

  if (valid == 0U)
  {
    (void)snprintf(line, n, "R:OVER %lu.%02luV", v_int, v_frac2);
    return;
  }

  if (rx_ohm >= 1000U)
  {
    uint32_t k = rx_ohm / 1000U;
    uint32_t frac1 = (rx_ohm % 1000U) / 100U; /* 1 digit */
    (void)snprintf(line, n, "R:%lu.%1luk %lu.%02luV", k, frac1, v_int, v_frac2);
  }
  else
  {
    (void)snprintf(line, n, "R:%luohm %lu.%02luV", rx_ohm, v_int, v_frac2);
  }
}


/* USER CODE END 0 */

/**
  * @brief  The application entry point.
  * @retval int
  */
int main(void)
{
  /* USER CODE BEGIN 1 */

  /* USER CODE END 1 */

  /* MCU Configuration--------------------------------------------------------*/

  /* Reset of all peripherals, Initializes the Flash interface and the Systick. */
  HAL_Init();

  /* USER CODE BEGIN Init */

  /* USER CODE END Init */

  /* Configure the system clock */
  SystemClock_Config();

  /* USER CODE BEGIN SysInit */

  /* USER CODE END SysInit */

  /* Initialize all configured peripherals */
  MX_GPIO_Init();
  MX_I2C1_Init();
  MX_RTC_Init();
  MX_ADC1_Init();
  /* USER CODE BEGIN 2 */
  i2c_scan_known();

#if DS1307_FORCE_SYNC_AT_BOOT
  if (has_rtc_68)
  {
    (void)ds1307_set_from_build_time();
  }
#endif

  if (lcd_init() == HAL_OK)
  {
    char line1[17];
    char line2[17];
    lcd_ready = 1U;

    (void)snprintf(line1, sizeof(line1), "I2C DEV:%02u", i2c_found_count);
    (void)snprintf(line2, sizeof(line2), "27:%u 3F:%u 68:%u",
                   has_lcd_27 ? 1U : 0U, has_lcd_3f ? 1U : 0U, has_rtc_68 ? 1U : 0U);
    lcd_print_line(0U, line1);
    lcd_print_line(1U, line2);
    HAL_Delay(1200);
  }
  last_update_ms = HAL_GetTick();
  b1_last_event_ms = HAL_GetTick();

  /* USER CODE END 2 */

  /* Infinite loop */
  /* USER CODE BEGIN WHILE */
  while (1)
  {
    /* USER CODE END WHILE */

    /* USER CODE BEGIN 3 */
    if (((HAL_GetTick() - last_update_ms) >= 200U) || (force_refresh_request != 0U))
    {
      ds1307_time_t now = {0};
      char line1[17];
      char line2[17];

      uint16_t adc_avg = 0U;
      uint32_t rx_ohm = 0U;
      uint32_t vout_mv = 0U;
      uint8_t rx_valid = 0U;

      last_update_ms = HAL_GetTick();
      force_refresh_request = 0U;

      if (lcd_ready)
      {
        if (zero_time_request != 0U)
        {
          (void)ds1307_set_time_zero();
          zero_time_request = 0U;
        }

        if (adc_read_avg_u12(&adc_avg) == HAL_OK)
        {
          rx_valid = calc_rx_ohm_from_adc(adc_avg, &rx_ohm, &vout_mv);
          format_resistance(line1, sizeof(line1), rx_ohm, rx_valid, vout_mv);
        }
        else
        {
          (void)snprintf(line1, sizeof(line1), "ADC READ ERROR");
        }

        if (ds1307_read(&now) == HAL_OK)
        {
          (void)snprintf(line2, sizeof(line2), "20%02u-%02u-%02u",
                         now.year, now.month, now.day);
        }
        else
        {
          (void)snprintf(line2, sizeof(line2), "RTC READ ERROR");
        }

        lcd_print_line(0U, line1);
        lcd_print_line(1U, line2);
      }
      else
      {
        HAL_GPIO_TogglePin(LD2_GPIO_Port, LD2_Pin);
      }
    }
    HAL_Delay(5);

  }
  /* USER CODE END 3 */
}

/**
  * @brief System Clock Configuration
  * @retval None
  */
void SystemClock_Config(void)
{
  RCC_OscInitTypeDef RCC_OscInitStruct = {0};
  RCC_ClkInitTypeDef RCC_ClkInitStruct = {0};

  /** Configure the main internal regulator output voltage
  */
  __HAL_RCC_PWR_CLK_ENABLE();
  __HAL_PWR_VOLTAGESCALING_CONFIG(PWR_REGULATOR_VOLTAGE_SCALE2);

  /** Initializes the RCC Oscillators according to the specified parameters
  * in the RCC_OscInitTypeDef structure.
  */
  RCC_OscInitStruct.OscillatorType = RCC_OSCILLATORTYPE_HSI|RCC_OSCILLATORTYPE_LSI;
  RCC_OscInitStruct.HSIState = RCC_HSI_ON;
  RCC_OscInitStruct.HSICalibrationValue = RCC_HSICALIBRATION_DEFAULT;
  RCC_OscInitStruct.LSIState = RCC_LSI_ON;
  RCC_OscInitStruct.PLL.PLLState = RCC_PLL_ON;
  RCC_OscInitStruct.PLL.PLLSource = RCC_PLLSOURCE_HSI;
  RCC_OscInitStruct.PLL.PLLM = 16;
  RCC_OscInitStruct.PLL.PLLN = 336;
  RCC_OscInitStruct.PLL.PLLP = RCC_PLLP_DIV4;
  RCC_OscInitStruct.PLL.PLLQ = 7;
  if (HAL_RCC_OscConfig(&RCC_OscInitStruct) != HAL_OK)
  {
    Error_Handler();
  }

  /** Initializes the CPU, AHB and APB buses clocks
  */
  RCC_ClkInitStruct.ClockType = RCC_CLOCKTYPE_HCLK|RCC_CLOCKTYPE_SYSCLK
                              |RCC_CLOCKTYPE_PCLK1|RCC_CLOCKTYPE_PCLK2;
  RCC_ClkInitStruct.SYSCLKSource = RCC_SYSCLKSOURCE_PLLCLK;
  RCC_ClkInitStruct.AHBCLKDivider = RCC_SYSCLK_DIV1;
  RCC_ClkInitStruct.APB1CLKDivider = RCC_HCLK_DIV2;
  RCC_ClkInitStruct.APB2CLKDivider = RCC_HCLK_DIV1;

  if (HAL_RCC_ClockConfig(&RCC_ClkInitStruct, FLASH_LATENCY_2) != HAL_OK)
  {
    Error_Handler();
  }
}

/**
  * @brief ADC1 Initialization Function
  * @param None
  * @retval None
  */
static void MX_ADC1_Init(void)
{

  /* USER CODE BEGIN ADC1_Init 0 */

  /* USER CODE END ADC1_Init 0 */

  ADC_ChannelConfTypeDef sConfig = {0};

  /* USER CODE BEGIN ADC1_Init 1 */

  /* USER CODE END ADC1_Init 1 */

  /** Configure the global features of the ADC (Clock, Resolution, Data Alignment and number of conversion)
  */
  hadc1.Instance = ADC1;
  hadc1.Init.ClockPrescaler = ADC_CLOCK_SYNC_PCLK_DIV4;
  hadc1.Init.Resolution = ADC_RESOLUTION_12B;
  hadc1.Init.ScanConvMode = DISABLE;
  hadc1.Init.ContinuousConvMode = DISABLE;
  hadc1.Init.DiscontinuousConvMode = DISABLE;
  hadc1.Init.ExternalTrigConvEdge = ADC_EXTERNALTRIGCONVEDGE_NONE;
  hadc1.Init.ExternalTrigConv = ADC_SOFTWARE_START;
  hadc1.Init.DataAlign = ADC_DATAALIGN_RIGHT;
  hadc1.Init.NbrOfConversion = 1;
  hadc1.Init.DMAContinuousRequests = DISABLE;
  hadc1.Init.EOCSelection = ADC_EOC_SINGLE_CONV;
  if (HAL_ADC_Init(&hadc1) != HAL_OK)
  {
    Error_Handler();
  }

  /** Configure for the selected ADC regular channel its corresponding rank in the sequencer and its sample time.
  */
  sConfig.Channel = ADC_CHANNEL_0;
  sConfig.Rank = 1;
  sConfig.SamplingTime = ADC_SAMPLETIME_84CYCLES;
  if (HAL_ADC_ConfigChannel(&hadc1, &sConfig) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN ADC1_Init 2 */

  /* USER CODE END ADC1_Init 2 */

}

/**
  * @brief I2C1 Initialization Function
  * @param None
  * @retval None
  */
static void MX_I2C1_Init(void)
{

  /* USER CODE BEGIN I2C1_Init 0 */

  /* USER CODE END I2C1_Init 0 */

  /* USER CODE BEGIN I2C1_Init 1 */

  /* USER CODE END I2C1_Init 1 */
  hi2c1.Instance = I2C1;
  hi2c1.Init.ClockSpeed = 100000;
  hi2c1.Init.DutyCycle = I2C_DUTYCYCLE_2;
  hi2c1.Init.OwnAddress1 = 0;
  hi2c1.Init.AddressingMode = I2C_ADDRESSINGMODE_7BIT;
  hi2c1.Init.DualAddressMode = I2C_DUALADDRESS_DISABLE;
  hi2c1.Init.OwnAddress2 = 0;
  hi2c1.Init.GeneralCallMode = I2C_GENERALCALL_DISABLE;
  hi2c1.Init.NoStretchMode = I2C_NOSTRETCH_DISABLE;
  if (HAL_I2C_Init(&hi2c1) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN I2C1_Init 2 */

  /* USER CODE END I2C1_Init 2 */

}

/**
  * @brief RTC Initialization Function
  * @param None
  * @retval None
  */
static void MX_RTC_Init(void)
{

  /* USER CODE BEGIN RTC_Init 0 */

  /* USER CODE END RTC_Init 0 */

  RTC_TimeTypeDef sTime = {0};
  RTC_DateTypeDef sDate = {0};

  /* USER CODE BEGIN RTC_Init 1 */

  /* USER CODE END RTC_Init 1 */

  /** Initialize RTC Only
  */
  hrtc.Instance = RTC;
  hrtc.Init.HourFormat = RTC_HOURFORMAT_24;
  hrtc.Init.AsynchPrediv = 127;
  hrtc.Init.SynchPrediv = 255;
  hrtc.Init.OutPut = RTC_OUTPUT_DISABLE;
  hrtc.Init.OutPutPolarity = RTC_OUTPUT_POLARITY_HIGH;
  hrtc.Init.OutPutType = RTC_OUTPUT_TYPE_OPENDRAIN;
  if (HAL_RTC_Init(&hrtc) != HAL_OK)
  {
    Error_Handler();
  }

  /* USER CODE BEGIN Check_RTC_BKUP */

  /* USER CODE END Check_RTC_BKUP */

  /** Initialize RTC and set the Time and Date
  */
  sTime.Hours = 0x0;
  sTime.Minutes = 0x0;
  sTime.Seconds = 0x0;
  sTime.DayLightSaving = RTC_DAYLIGHTSAVING_NONE;
  sTime.StoreOperation = RTC_STOREOPERATION_RESET;
  if (HAL_RTC_SetTime(&hrtc, &sTime, RTC_FORMAT_BCD) != HAL_OK)
  {
    Error_Handler();
  }
  sDate.WeekDay = RTC_WEEKDAY_MONDAY;
  sDate.Month = RTC_MONTH_JANUARY;
  sDate.Date = 0x1;
  sDate.Year = 0x0;

  if (HAL_RTC_SetDate(&hrtc, &sDate, RTC_FORMAT_BCD) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN RTC_Init 2 */

  /* USER CODE END RTC_Init 2 */

}

/**
  * @brief GPIO Initialization Function
  * @param None
  * @retval None
  */
static void MX_GPIO_Init(void)
{
  GPIO_InitTypeDef GPIO_InitStruct = {0};

  /* GPIO Ports Clock Enable */
  __HAL_RCC_GPIOC_CLK_ENABLE();
  __HAL_RCC_GPIOH_CLK_ENABLE();
  __HAL_RCC_GPIOA_CLK_ENABLE();
  __HAL_RCC_GPIOB_CLK_ENABLE();

  /*Configure GPIO pin Output Level */
  HAL_GPIO_WritePin(LD2_GPIO_Port, LD2_Pin, GPIO_PIN_RESET);

  /*Configure GPIO pin : B1_Pin */
  GPIO_InitStruct.Pin = B1_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_IT_FALLING;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  HAL_GPIO_Init(B1_GPIO_Port, &GPIO_InitStruct);

  /*Configure GPIO pins : USART_TX_Pin USART_RX_Pin */
  GPIO_InitStruct.Pin = USART_TX_Pin|USART_RX_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_AF_PP;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  GPIO_InitStruct.Alternate = GPIO_AF7_USART2;
  HAL_GPIO_Init(GPIOA, &GPIO_InitStruct);

  /*Configure GPIO pin : LD2_Pin */
  GPIO_InitStruct.Pin = LD2_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(LD2_GPIO_Port, &GPIO_InitStruct);

}

/* USER CODE BEGIN 4 */
void HAL_GPIO_EXTI_Callback(uint16_t GPIO_Pin)
{
  uint32_t now = HAL_GetTick();

  if (GPIO_Pin != B1_Pin)
  {
    return;
  }

  if ((now - b1_last_event_ms) < B1_DEBOUNCE_MS)
  {
    return;
  }

  b1_last_event_ms = now;
  zero_time_request = 1U;
  force_refresh_request = 1U;
}

/* USER CODE END 4 */

/**
  * @brief  This function is executed in case of error occurrence.
  * @retval None
  */
void Error_Handler(void)
{
  /* USER CODE BEGIN Error_Handler_Debug */
  /* User can add his own implementation to report the HAL error return state */
  __disable_irq();
  while (1)
  {
  }
  /* USER CODE END Error_Handler_Debug */
}

#ifdef  USE_FULL_ASSERT
/**
  * @brief  Reports the name of the source file and the source line number
  *         where the assert_param error has occurred.
  * @param  file: pointer to the source file name
  * @param  line: assert_param error line source number
  * @retval None
  */
void assert_failed(uint8_t *file, uint32_t line)
{
  /* USER CODE BEGIN 6 */
  /* User can add his own implementation to report the file name and line number,
     ex: printf("Wrong parameters value: file %s on line %d\r\n", file, line) */
  /* USER CODE END 6 */
}
#endif /* USE_FULL_ASSERT */
