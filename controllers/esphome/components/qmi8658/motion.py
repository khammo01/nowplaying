import esphome.codegen as cg
from esphome.components import i2c
from esphome.components.const import (
    CONF_ACCELEROMETER_ODR,
    CONF_ACCELEROMETER_RANGE,
)
from esphome.components.motion import motion_schema, new_motion_component
import esphome.config_validation as cv
from esphome.types import ConfigType

from . import QMI8658Component, qmi8658_ns

#  Enum proxies (must match the C++ enum values exactly)
QMI8658AccelRange = qmi8658_ns.enum("QMI8658AccelRange")
ACCEL_RANGE_OPTIONS = {
    "2G": QMI8658AccelRange.QMI8658_ACCEL_RANGE_2G,
    "4G": QMI8658AccelRange.QMI8658_ACCEL_RANGE_4G,
    "8G": QMI8658AccelRange.QMI8658_ACCEL_RANGE_8G,
    "16G": QMI8658AccelRange.QMI8658_ACCEL_RANGE_16G,
}

QMI8658AccelODR = qmi8658_ns.enum("QMI8658AccelODR")
ACCEL_ODR_OPTIONS = {
    "31_25HZ": QMI8658AccelODR.QMI8658_ACCEL_ODR_31_25,
    "62_5HZ": QMI8658AccelODR.QMI8658_ACCEL_ODR_62_5,
    "125HZ": QMI8658AccelODR.QMI8658_ACCEL_ODR_125,
    "250HZ": QMI8658AccelODR.QMI8658_ACCEL_ODR_250,
    "500HZ": QMI8658AccelODR.QMI8658_ACCEL_ODR_500,
    "1000HZ": QMI8658AccelODR.QMI8658_ACCEL_ODR_1000,
    "2000HZ": QMI8658AccelODR.QMI8658_ACCEL_ODR_2000,
    "4000HZ": QMI8658AccelODR.QMI8658_ACCEL_ODR_4000,
    "8000HZ": QMI8658AccelODR.QMI8658_ACCEL_ODR_8000,
}

#  Top-level CONFIG_SCHEMA
CONFIG_SCHEMA = (
    motion_schema(QMI8658Component, has_accel=True, has_gyro=False)
    .extend(
        {
            cv.Optional(CONF_ACCELEROMETER_RANGE, default="4G"): cv.enum(
                ACCEL_RANGE_OPTIONS, upper=True
            ),
            cv.Optional(CONF_ACCELEROMETER_ODR, default="1000HZ"): cv.enum(
                ACCEL_ODR_OPTIONS, upper=True
            ),
        }
    )
    .extend(i2c.i2c_device_schema(0x6B))
)


#  Code generation
async def to_code(config: ConfigType) -> None:
    var = await new_motion_component(config)
    await i2c.register_i2c_device(var, config)

    # Hardware configuration
    cg.add(var.set_accel_range(config[CONF_ACCELEROMETER_RANGE]))
    cg.add(var.set_accel_odr(config[CONF_ACCELEROMETER_ODR]))
