with Ada.Real_Time; use Ada.Real_Time;

with Types; use Types;
with LEDS_Pack; use LEDS_Pack;
with IMU_Pack; use IMU_Pack;
with Motors_Pack; use Motors_Pack;
with Communication_Pack; use Communication_Pack;
with Commander_Pack; use Commander_Pack;
with Stabilizer_Pack; use Stabilizer_Pack;
with Console_Pack; use Console_Pack;

package body System_Pack is

   procedure System_Init is
   begin
      if Is_Init then
         return;
      end if;
      --  Module initialization

      --  Initialize LEDs, sensors and actuators
      LEDS_Init;
      Motors_Init;

      --  Initialize communication related modules
      Communication_Init;

      --  Initialize high level modules
      Commander_Init;

      Is_Init := True;
   end System_Init;

   function System_Self_Test return Boolean is
      Self_Test_Passed : Boolean;
   begin
      Self_Test_Passed := LEDS_Test;
      Self_Test_Passed := Self_Test_Passed and Motors_Test;
      Self_Test_Passed := Self_Test_Passed and Communication_Test;
      Self_Test_Passed := Self_Test_Passed and Commander_Test;

      return Self_Test_Passed;
   end System_Self_Test;

   procedure System_Loop is
      Attitude_Update_Counter : T_Uint32 := 0;
      Alt_Hold_Update_Counter : T_Uint32 := 0;
      Next_Period             : Time;
      Has_Succeed             : Boolean;
   begin
      Next_Period := Clock + Milliseconds (IMU_UPDATE_DT_MS);

      loop
         delay until Next_Period;

         Console_Put_Line ("Loop called", Has_Succeed);
         Stabilizer_Control_Loop (Attitude_Update_Counter,
                                  Alt_Hold_Update_Counter);

         Next_Period := Clock + Milliseconds (IMU_UPDATE_DT_MS);
      end loop;
   end System_Loop;

end System_Pack;