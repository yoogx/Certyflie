with Ada.Numerics; use Ada.Numerics;
with Ada.Real_Time; use Ada.Real_Time;

with Types; use Types;
with Filter_Pack; use Filter_Pack;
with MPU9250_Pack; use MPU9250_Pack;

package IMU_Pack
with SPARK_Mode
is

   --  Types

   --  These ranges are deduced from the MPU9150 specification.
   --  It corresponds to the maximum range of values that can be output
   --  by the IMU.

   --  Type for angular speed output from gyro, degrees/s
   subtype T_Rate is Float range -3_000.0  .. 3_000.0;
   --  Type for angular speed output from gyro, rad/s
   subtype T_Rate_Rad
     is Float range -3_000.0 * Pi / 180.0 .. 3_000.0 * Pi / 180.0;
   --  Type for acceleration output from accelerometer, in G
   subtype T_Acc  is Float range -16.0 .. 16.0;
   --  Type for magnetometer output, in micro-Teslas
   subtype T_Mag  is Float range -1_200.0  .. 1_200.0;

   --  Type used when we want to collect several accelerometer samples
   type T_Acc_Array is array (Integer range <>) of T_Acc;

   --  Type used to ensure that accelation normalization can't lead to a
   --  division by zero in SensFusion6_Pack algorithms
   MIN_NON_ZERO_ACC : constant := 2.0 ** (-74);

   subtype T_Acc_Lifted is T_Acc; -- with
   --         Static_Predicate => T_Acc_Lifted = 0.0 or else
   --         T_Acc_Lifted not in -MIN_NON_ZERO_ACC .. MIN_NON_ZERO_ACC;

   type Gyroscope_Data is record
      X : T_Rate;
      Y : T_Rate;
      Z : T_Rate;
   end record;

   type Accelerometer_Data is record
      X : T_Acc;
      Y : T_Acc;
      Z : T_Acc;
   end record;

   type Magnetometer_Data is record
      X : T_Mag;
      Y : T_Mag;
      Z : T_Mag;
   end record;

   --  Global variables and constants

   IMU_UPDATE_FREQ  : constant := 500.0;
   IMU_UPDATE_DT    : constant := 1.0 / IMU_UPDATE_FREQ;
   IMU_UPDATE_DT_MS : constant Time_Span := Milliseconds (2);

   --  Number of samples used for bias calculation
   IMU_NBR_OF_BIAS_SAMPLES      : constant := 32;
   GYRO_MIN_BIAS_TIMEOUT_MS     : constant Time_Span := Milliseconds (1_000);

   --  Set ACC_WANTED_LPF1_CUTOFF_HZ to the wanted cut-off freq in Hz.
   --  The highest cut-off freq that will have any affect is fs /(2*pi).
   --  E.g. fs = 350 Hz -> highest cut-off = 350/(2*pi) = 55.7 Hz -> 55 Hz
   IMU_ACC_WANTED_LPF_CUTOFF_HZ : constant := 4.0;
   --  Attenuation should be between 1 to 256.
   --  F0 = fs / 2*pi*attenuation ->
   --  Attenuation = fs / 2*pi*f0
   IMU_ACC_IIR_LPF_ATTENUATION  : constant Float
     := Float (IMU_UPDATE_FREQ) / (2.0 * Pi * IMU_ACC_WANTED_LPF_CUTOFF_HZ);
   IMU_ACC_IIR_LPF_ATT_FACTOR   : constant T_Uint8
     := T_Uint8 (Float (2 ** IIR_SHIFT) / IMU_ACC_IIR_LPF_ATTENUATION + 0.5);

   GYRO_VARIANCE_BASE        : constant := 2000;
   GYRO_VARIANCE_THRESHOLD_X : constant := (GYRO_VARIANCE_BASE);
   GYRO_VARIANCE_THRESHOLD_Y : constant := (GYRO_VARIANCE_BASE);
   GYRO_VARIANCE_THRESHOLD_Z : constant := (GYRO_VARIANCE_BASE);

   IMU_DEG_PER_LSB_CFG       : constant := MPU9250_DEG_PER_LSB_2000;
   IMU_G_PER_LSB_CFG         : constant := MPU9250_G_PER_LSB_8;

   IMU_VARIANCE_MAN_TEST_TIMEOUT : constant Time_Span := Milliseconds (1_000);
   IMU_MAN_TEST_LEVEL_MAX : constant := 5.0;

   --  Procedures and functions

   --  Initialize the IMU device/
   procedure IMU_Init;

   --  Test if the IMU device is initialized/
   function IMU_Test return Boolean;

   --  Manufacting test to ensure that IMU is not broken.
   function IMU_6_Manufacturing_Test return Boolean;

   procedure IMU_6_Read
     (Gyro : in out Gyroscope_Data;
      Acc  : in out Accelerometer_Data)
     with
       Global => null;

   --  Read gyro, accelerometer and magnetometer measurements.
   procedure IMU_9_Read
     (Gyro : in out Gyroscope_Data;
      Acc  : in out Accelerometer_Data;
      Mag  : in out Magnetometer_Data)
     with
       Global => null;

   --  Return True if the IMU is correctly calibrated, False otherwise.
   function IMU_6_Calibrated return Boolean;

   --  Return True if the IMU has an initialized barometer, False otherwise.
   function IMU_Has_Barometer return Boolean;

private
   --  Types

   type Axis3_T_Int16 is record
      X : T_Int16 := 0;
      Y : T_Int16 := 0;
      Z : T_Int16 := 0;
   end record;

   type Axis3_T_Int32 is record
      X : T_Int32 := 0;
      Y : T_Int32 := 0;
      Z : T_Int32 := 0;
   end record;

   type Axis3_Float is record
      X : Float := 0.0;
      Y : Float := 0.0;
      Z : Float := 0.0;
   end record;

   type Bias_Buffer_Array is
     array (1 .. IMU_NBR_OF_BIAS_SAMPLES) of Axis3_T_Int16;

   --  Type used for bias calculation
   type Bias_Object is record
      Bias                : Axis3_T_Int16;
      Buffer              : Bias_Buffer_Array;
      Buffer_Index        : Positive := Bias_Buffer_Array'First;
      Is_Bias_Value_Found : Boolean  := False;
      Is_Buffer_Filled    : Boolean  := False;
   end record;

   --  Global variables and constants

   Is_Init : Boolean := False;
   --  Barometer and magnetometr not avalaible for now.
   --  TODO: add the code to manipulate them
   Is_Barometer_Avalaible   : Boolean := False;
   Is_Magnetomer_Availaible : Boolean := False;
   Is_Calibrated            : Boolean := False;

   Variance_Sample_Time  : Time;
   IMU_Acc_Lp_Att_Factor : T_Uint8;

   --  Raw values retrieved from IMU
   Accel_IMU           : Axis3_T_Int16;
   Gyro_IMU            : Axis3_T_Int16;
   --  Acceleration after applying the IIR LPF filter
   Accel_LPF           : Axis3_T_Int16;
   --  Use to stor the IIR LPF filter feedback
   Accel_Stored_Values : Axis3_T_Int32;
   --  Acceleration after aligning with gravity
   Accel_LPF_Aligned   : Axis3_Float;

   Cos_Pitch : Float;
   Sin_Pitch : Float;
   Cos_Roll  : Float;
   Sin_Roll  : Float;

   --  Bias objects used for bias calculation
   Gyro_Bias : Bias_Object;

   --  Procedures and functions

   --  Add a new value to the variance buffer and if it is full
   --  replace the oldest one. Thus a circular buffer.
   procedure IMU_Add_Bias_Value
     (Bias_Obj : in out Bias_Object;
      Value    : Axis3_T_Int16);

   --  Check if the variances is below the predefined thresholds.
   --  The bias value should have been added before calling this.
   procedure IMU_Find_Bias_Value
     (Bias_Obj       : in out Bias_Object;
      Has_Found_Bias : out Boolean);

   --  Calculate the variance and mean for the bias buffer.
   procedure IMU_Calculate_Variance_And_Mean
     (Bias_Obj : Bias_Object;
      Variance : out Axis3_T_Int16;
      Mean     : out Axis3_T_Int16);

   --  Apply IIR LP Filter on each axis.
   procedure IMU_Acc_IRR_LP_Filter
     (Input         : Axis3_T_Int16;
      Output        : out Axis3_T_Int16;
      Stored_Values : in out Axis3_T_Int32;
      Attenuation   : T_Int32);

   --  Compensate for a miss-aligned accelerometer. It uses the trim
   --  data gathered from the UI and written in the config-block to
   --  rotate the accelerometer to be aligned with gravity.
   procedure IMU_Acc_Align_To_Gravity
     (Input  : Axis3_T_Int16;
      Output : out Axis3_Float);

end IMU_Pack;
