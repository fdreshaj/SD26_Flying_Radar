# -*- coding: utf-8 -*-

# This example connects to a networked device such as the SM200C
# and performs a speed test.

from smdevice.sm_api import *

def speed_test():
    # Open device
    handle = sm_open_networked_device(SM200_ADDR_ANY, SM200_DEFAULT_ADDR, SM200_DEFAULT_PORT)["device"]

    # Run test
    for i in range(5): # Sometimes needs some ramp-up time
        bytes_per_sec = sm_networked_speed_test(handle, 1)["bytes_per_second"]
    print (f"\nSpeed: {bytes_per_sec * 8 / 1e9} Gb/s")

if __name__ == "__main__":
    speed_test()
