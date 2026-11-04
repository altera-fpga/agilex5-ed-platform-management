# QT Py RP2040 sensor-board firmware -- v1 "heater-only" (legacy format).
#
# Reads the potentiometer on A0, drives the heater PWM on A2 at 20 kHz, and
# streams the raw knob value over the hardware UART at 115200 baud as a single
# line "Heater: <value>".
#
# Uses only modules built into CircuitPython, so CIRCUITPY/lib/ can be empty.
# Compatible with ANY release of the qtpy-uart-bridge (the bridge still parses
# this legacy single-line format). Use this if your BMC image predates the
# v2 "rack" firmware / fault-flagging feature.
print("Starting!")

import time
import board
import busio
import pwmio
import analogio


knobIn = analogio.AnalogIn(board.A0)
pwmOut = pwmio.PWMOut(board.A2, frequency=20000, duty_cycle=0)

uart = busio.UART(board.TX, board.RX, baudrate=115200, timeout=0)

while True:
    burn = knobIn.value
    pwmOut.duty_cycle = burn
    uart.write(f"Heater: {burn}\n".encode("utf-8"))
    time.sleep(0.1)
