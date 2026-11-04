print("Starting!")

import time
import board
import busio
import pwmio
import analogio 
from adafruit_bus_device.i2c_device import I2CDevice

DEBUG = False  # flip this one line

def dbg(*args, **kwargs):
    if DEBUG:
        print(*args, **kwargs)

INP0 = 0x00
INP1 = 0x01
LED1R = 0x20
LED1G = 0x21
LED1B = 0x22
LED2R = 0x24
LED2G = 0x25
LED2B = 0x26
LED3R = 0x27
LED3G = 0x28
LED3B = 0x29
LED4R = 0x2A
LED4G = 0x2B
LED4B = 0x2C

mcp3221data = bytearray(2)

knobIn = analogio.AnalogIn(board.A0)
pwmOut = pwmio.PWMOut(board.A2, frequency=20000, duty_cycle=0)

uart = busio.UART(board.TX, board.RX, baudrate=115200, timeout=0)

try: 
    i2c = board.STEMMA_I2C()
except:
    print("No I2C")
    i2c = None
    mcp3221 = None
    aw9523 = None

if i2c:
    try:
        mcp3221 = I2CDevice(i2c, 0x4D)
    except (ValueError, OSError):
        mcp3221 = None
        print("MCP3221 not found")

    aw9523data = bytearray(1)
    try:
        aw9523 = I2CDevice(i2c, 0x5B)
    except (ValueError, OSError):
        aw9523 = None
        print("AW9523 not found")

    while not i2c.try_lock():
        pass

    if aw9523:
        aw9523.write_then_readinto(bytes([0x10]), aw9523data)
        if (aw9523data[0] != 0x23):
            aw9523 = None
            print("AW9523 not found")

    if aw9523:
        aw9523.write(bytes([0x04, 0xFF]))
        aw9523.write(bytes([0x05, 0xFF]))
        aw9523.write(bytes([0x11, 0x03]))
        aw9523.write(bytes([0x12, 0x00]))
        aw9523.write(bytes([0x13, 0xE0]))
        aw9523.write(bytes([LED1G, 0x04]))
        print("AW9523 present")

if mcp3221:
    print("Starting loop controlled by I2C ADC")
else:
    print("Starting loop controlled by analog input")

while True:
    if mcp3221:
        mcp3221.readinto(mcp3221data)
        burn = (mcp3221data[0] << 12) | (mcp3221data[1] << 4)
    else:
        burn = knobIn.value
    dbg("Heater setting: ", burn)  
    if aw9523:
        aw9523.write(bytes([LED1R, (burn>>8)]))
        aw9523.write_then_readinto(bytes([INP1]), aw9523data)
        switches = aw9523data[0]>>5
        if ((switches & 0x01)==0x1): 
            aw9523.write(bytes([LED4R, 0x10]))
            aw9523.write(bytes([LED4G, 0x00]))
        else:
            aw9523.write(bytes([LED4R, 0x00]))
            aw9523.write(bytes([LED4G, 0x04]))    
        if ((switches & 0x02)==0x2): 
            aw9523.write(bytes([LED3R, 0x10]))
            aw9523.write(bytes([LED3G, 0x00]))
        else:
            aw9523.write(bytes([LED3R, 0x00]))
            aw9523.write(bytes([LED3G, 0x04]))    
        if ((switches & 0x04)==0x4): 
            aw9523.write(bytes([LED2R, 0x10]))
            aw9523.write(bytes([LED2G, 0x00]))
        else:
            aw9523.write(bytes([LED2R, 0x00]))
            aw9523.write(bytes([LED2G, 0x04]))    
        dbg("write LEDs ", switches)
    pwmOut.duty_cycle = burn
    uart.write(f'{{ "profile": "CoolingDistributionUnit",\n'.encode("utf-8"))
    uart.write(f'  "heater": {burn},\n'.encode("utf-8"))
    uart.write(f'  "messages": [\n'.encode("utf-8"))
    if aw9523:
        if ((switches & 0x01)==0x1):        
            uart.write(f'    "text": "Leak Detected",\n'.encode("utf-8"))
            dbg("Leak detected")
        if ((switches & 0x02)==0x2):        
            uart.write(f'    "text": "Pump Failed",\n'.encode("utf-8"))
            dbg("Pump failure")
        if ((switches & 0x04)==0x4):        
            uart.write(f'    "text": "Fan Failed",\n'.encode("utf-8"))
            dbg("Fan failure")
    uart.write(f'] }}\n'.encode("utf-8"))
    time.sleep(0.1)
