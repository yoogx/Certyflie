###############################################################################
# General makefile for Certyflie
#
# This makefile assumes SPARK and GNAT for ARM toolset are in the PATH.
# Tested with SPARK GPL Discovery 2017 ans GNAT GPL 2017

###############################################################################
# Compute path to Ada RTS, see SPARK User's Guide 7.1.3 for details
# http://docs.adacore.com/spark2014-docs/html/ug/index.html

ada_rts=$$(dirname $$(arm-eabi-gnatls -v --RTS=ravenscar-full-stm32f4 | grep adalib))

###############################################################################
# The following files are the only one with SPARK_Mode activated

file=modules/commander.adb modules/controller.adb			\
	modules/free_fall.adb modules/pid.adb modules/stabilizer.adb

###############################################################################
# General rules

help:
	@echo "Available targets"
	@echo " compile : compile Crazyflie firmware"
	@echo " prove   : call gnatprove on selected files"
	@echo " clean   : clean up directories"

compile:
	gprbuild -Pcf_ada_spark.gpr

prove:
	gnatprove -P cf_ada_spark.gpr --warnings=continue --report=statistics --RTS=$(ada_rts) --prover=alt-ergo,cvc4 --no-inlining --level=4 -u $(file)

# For SPARK GPL 2017, we need
# --RTS to specifiy runtime, see SPARK UG 7.1.3
# --no-inlining, see https://github.com/yoogx/Certyflie/issues/1
#
# also, we pass a list of files, the ones with SPARK_Mode activated

clean:
	gnatprove -P cf_ada_spark.gpr --clean --RTS=$(ada_rts)
