#!/usr/bin/env python3

import json
import logging
import os
import subprocess
import time

from src import CHROME_DRIVER, CONFIG_FILE, ROOT
from src import log

log.init()
logger = logging.getLogger('app')


def symlink_force(target, link_name):
    try:
        os.symlink(target, link_name)
    except OSError as e:
        import errno
        if e.errno == errno.EEXIST:
            os.remove(link_name)
            os.symlink(target, link_name)


def get_or_raise(env: str) -> str:
    """
    Check if needed environment variables are given.

    :param env: key
    :return: value
    """
    env_value = os.getenv(env)
    if not env_value:
        raise RuntimeError('The environment variable {0:s} is missing.'
                           'Please check docker image or Dockerfile!'.format(env))
    return env_value


def convert_str_to_bool(str: str) -> bool:
    """
    Convert string to boolean.

    :param str: given string
    :return: converted string
    """
    try:
        return str.lower() in ('yes', 'true', 't', '1')
    except AttributeError as err:
        logger.error(err)


def get_env_int(env_name: str, default_value: int) -> int:
    """
    Safely get integer value from environment variable.
    
    :param env_name: Environment variable name
    :param default_value: Default value if env var is not set or invalid
    :return: Integer value
    """
    try:
        value = os.getenv(env_name)
        if value is None:
            return default_value
        return int(value)
    except (ValueError, TypeError):
        logger.warning(f"Invalid integer value for {env_name}: {os.getenv(env_name)}, using default: {default_value}")
        return default_value


def get_env_port_from_udid(default_port: str = "5554") -> str:
    """
    Safely extract port from UDID environment variable.
    
    :param default_port: Default port if UDID is not set or invalid
    :return: Port string
    """
    udid = os.getenv('UDID')
    if udid is None:
        logger.warning(f"UDID environment variable not set, using default port: {default_port}")
        return default_port
    
    if 'emulator-' in udid:
        try:
            return udid.replace('emulator-', '')
        except AttributeError:
            logger.warning(f"Invalid UDID format: {udid}, using default port: {default_port}")
            return default_port
    else:
        logger.warning(f"UDID does not contain 'emulator-' prefix: {udid}, using as-is")
        return udid


def is_initialized(device_name) -> bool:
    config_path = os.path.join(ROOT, 'android_emulator', 'config.ini')

    if os.path.exists(config_path):
        logger.info('Found existing config file at {}.'.format(config_path))
        with open(config_path, 'r') as f:
            if any('hw.device.name={}'.format(device_name) in line for line in f):
                logger.info('Existing config file references {}. Assuming device was previously initialized.'.format(device_name))
                return True
            else:
                logger.info('Existing config file does not reference {}. Assuming new device.'.format(device_name))
                return False

    logger.info('No config file file was found at {}. Assuming new device.'.format(config_path))
    return False


ANDROID_HOME = '/root'
ANDROID_VERSION = get_or_raise('ANDROID_VERSION')
API_LEVEL = get_or_raise('API_LEVEL')
PROCESSOR = get_or_raise('PROCESSOR')
SYS_IMG = get_or_raise('SYS_IMG')
IMG_TYPE = get_or_raise('IMG_TYPE')

logger.info('Android version: {version} \n'
            'API level: {level} \n'
            'Processor: {processor} \n'
            'System image: {img} \n'
            'Image type: {img_type}'.format(version=ANDROID_VERSION, level=API_LEVEL, processor=PROCESSOR,
                                            img=SYS_IMG, img_type=IMG_TYPE))


def prepare_avd(device: str, avd_name: str, dp_size: str):
    """
    Create and run android virtual device.

    :param device: Device name
    :param avd_name: Name of android virtual device / emulator
    """

    device_name_bash = device.replace(' ', r'\ ')
    skin_name = device.replace(' ', '_').lower()

    # For custom hardware profile
    profile_dst_path = os.path.join(ROOT, '.android', 'devices.xml')
    if 'samsung' in device.lower():
        # profile file name = skin name
        profile_src_path = os.path.join(ROOT, 'devices', 'profiles', '{profile}.xml'.format(profile=skin_name))
        logger.info('Hardware profile resource path: {rsc}'.format(rsc=profile_src_path))
        logger.info('Hardware profile destination path: {dst}'.format(dst=profile_dst_path))
        symlink_force(profile_src_path, profile_dst_path)

    avd_path = '/'.join([ANDROID_HOME, 'android_emulator'])
    creation_cmd = 'avdmanager create avd -f -n {name} -b {img_type}/{sys_img} -k "system-images;android-{api_lvl};' \
                   '{img_type};{sys_img}" -d {device} -p {path}'.format(name=avd_name, img_type=IMG_TYPE,
                                                                        sys_img=SYS_IMG,
                                                                        api_lvl=API_LEVEL, device=device_name_bash,
                                                                        path=avd_path)
    logger.info('Command to create avd: {command}'.format(command=creation_cmd))
    subprocess.check_call(creation_cmd, shell=True)

    skin_path = '/'.join([ANDROID_HOME, 'devices', 'skins', skin_name])
    config_path = '/'.join([avd_path, 'config.ini'])
    ram_size = os.getenv('RAM', '8192m')
    with open(config_path, 'a') as file:
        file.write('skin.path={sp}'.format(sp=skin_path))
        logger.info('Skin was added in config.ini')
        file.write('\ndisk.dataPartition.size={dp}'.format(dp=dp_size))
        file.write('\nhw.ramSize={ram}'.format(ram=ram_size))
        file.write('\nhw.audioOutput=no')
        # file.write('\nhw.gsmModem=no')
        file.write('\nhw.sensors.light=no')
        file.write('\nhw.sensors.pressure=no')
        file.write('\nhw.sensors.humidity=no')
        file.write('\nhw.sensors.magnetic_field=no')
        file.write('\nhw.sensors.magnetic_field_uncalibrated=no')
        file.write('\nhw.sensors.gyroscope_uncalibrated=no')
        file.write('\nhw.sensors.temperature=no')
        file.write('\nhw.sensors.hinge=no')
    with open(config_path, 'r') as fi:
        lines = fi.readlines()
    with open(config_path, 'w') as fi:
        for line in lines:
            if 'hw.audioInput=yes' in line:
                line = line.replace('hw.audioInput=yes', 'hw.audioInput=no')
            elif 'hw.battery=yes' in line:
                line = line.replace('hw.battery=yes', 'hw.battery=no')
            # elif 'hw.gps=yes' in line:
            #     line = line.replace('hw.gps=yes', 'hw.gps=no')
            elif 'hw.sdCard=yes' in line:
                line = line.replace('hw.sdCard=yes', 'hw.sdCard=no')
            # elif 'hw.accelerometer=yes' in line:
            #     line = line.replace('hw.accelerometer=yes', 'hw.accelerometer=no')
            elif 'hw.sensors.orientation=yes' in line:
                line = line.replace('hw.sensors.orientation=yes', 'hw.sensors.orientation=no')
            elif 'hw.sensors.proximity=yes' in line:
                line = line.replace('hw.sensors.proximity=yes', 'hw.sensors.proximity=no')
            elif 'hw.lcd.density=480' in line:
                line = line.replace('hw.lcd.density=480', 'hw.lcd.density=420')
            fi.write(line)


def appium_run(avd_name: str):
    """
    Run appium server.

    :param avd_name: Name of android virtual device / emulator
    """
    appium_port = get_env_int('APPIUM_PORT', 4723)
    default_capabilities = os.getenv('DEFAULT_CAPABILITIES', '')
    DEFAULT_LOG_PATH = '/var/log/supervisor/appium_logs/appium_{port}.log'.format(port=appium_port)

    cmd = 'appium --log {log} -p {appium_port} --log-timestamp --local-timezone --session-override ' \
          '--base-path /wd/hub --use-plugins=relaxed-caps,images' \
        .format(log=os.getenv('APPIUM_LOG', DEFAULT_LOG_PATH), appium_port=appium_port)

    relaxed_security = convert_str_to_bool(str(os.getenv('RELAXED_SECURITY', True)))
    logger.info('Relaxed security? {rs}'.format(rs=relaxed_security))
    if relaxed_security:
        cmd += ' --relaxed-security'
    if default_capabilities:
        cmd += " --default-capabilities '{default_capabilities}'".format(default_capabilities=default_capabilities)

    default_web_browser = os.getenv('BROWSER')
    # cmd += ' --chromedriver-executable {driver}'.format(driver=CHROME_DRIVER)
    logger.info("appium command: {command}".format(command=cmd))

    grid_connect = convert_str_to_bool(str(os.getenv('CONNECT_TO_GRID', False)))
    logger.info('Connect to selenium grid? {connect}'.format(connect=grid_connect))
    if grid_connect:
        # Ubuntu 16.04 -> local_ip = os.popen('ifconfig eth0 | grep \'inet addr:\' | cut -d: -f2 | awk \'{ print $1}\'').read().strip()
        local_ip = os.popen('ifconfig eth0 | grep \'inet\' | cut -d: -f2 | awk \'{ print $2}\'').read().strip()
        try:
            mobile_web_test = convert_str_to_bool(str(os.getenv('MOBILE_WEB_TEST', False)))
            appium_host = os.getenv('APPIUM_HOST', local_ip)
            appium_port = get_env_int('APPIUM_PORT', 4723)
            selenium_host = os.getenv('SELENIUM_HOST', '172.17.0.1')
            selenium_port = get_env_int('SELENIUM_PORT', 4444)
            selenium_timeout = get_env_int('SELENIUM_TIMEOUT', 30)
            browser_name = default_web_browser if mobile_web_test else 'android'
            create_node_config(avd_name, browser_name, appium_host, appium_port, selenium_host, selenium_port,
                               selenium_timeout)
            cmd += ' --nodeconfig {file}'.format(file=CONFIG_FILE)
        except ValueError as v_err:
            logger.error(v_err)
    title = 'Appium Server'
    subprocess.check_call('xterm -T "{title}" -n "{title}" -e \"{cmd}\"'.format(title=title, cmd=cmd), shell=True)

# Deprecated
def back_appium_run():
    """run this appium background to resolve some tasks
    """
    appium_port = get_env_int('APPIUM_PORT', 4723)
    appium_port2 = appium_port + 1
    os.environ['APPIUM_PORT2'] = str(appium_port2)
    logger.info(f"APPIUM_PORT2 set to: {os.getenv('APPIUM_PORT2')}")
    cmd = 'appium -p {appium_port} --relaxed-security --log-timestamp --local-timezone --session-override ' \
          '--base-path /wd/hub --use-plugins=relaxed-caps,images' \
        .format(appium_port=appium_port2)
    logger.info("appium2 command: {command}".format(command=cmd))
    try:
        subprocess.Popen(cmd.split())
        logger.info("Command executed successfully.")
    except Exception as e:
        logger.error(f"Error executing command: {e}")


def create_node_config(avd_name: str, browser_name: str, appium_host: str, appium_port: int, selenium_host: str,
                       selenium_port: int, selenium_timeout: int):
    """
    Create custom node config file in json format to be able to connect with selenium server.

    :param avd_name: Name of android virtual device / emulator
    :param appium_host: Host where appium server is running
    :param appium_port: Port number where where appium server is running
    :param selenium_host: Host where selenium server is running
    :param selenium_port: Port number where selenium server is running
    :param selenium_timeout: Selenium session timeout in seconds
    """
    config = {
        'capabilities': [
            {
                'platform': 'Android',
                'platformName': 'Android',
                'version': ANDROID_VERSION,
                'browserName': browser_name,
                'deviceName': avd_name,
                'maxInstances': 1,
            }
        ],
        'configuration': {
            'cleanUpCycle': 2000,
            'timeout': selenium_timeout,
            'proxy': 'org.openqa.grid.selenium.proxy.DefaultRemoteProxy',
            'url': 'http://{host}:{port}/wd/hub'.format(host=appium_host, port=appium_port),
            'host': appium_host,
            'port': appium_port,
            'maxSession': 6,
            'register': True,
            'registerCycle': 5000,
            'hubHost': selenium_host,
            'hubPort': selenium_port,
            'unregisterIfStillDownAfter': 120000
        }
    }
    logger.info('Appium node config: {config}'.format(config=config))
    with open(CONFIG_FILE, 'w') as cf:
        cf.write(json.dumps(config))


def run():
    """Run app."""
    device = os.getenv('DEVICE', 'Nexus 5')
    logger.info('Device: {device}'.format(device=device))
    custom_args=os.getenv('EMULATOR_ARGS', '')
    logger.info('Custom Args: {custom_args}'.format(custom_args=custom_args))

    avd_name = os.getenv('AVD_NAME', '{device}_{version}'.format(device=device.replace(' ', '_').lower(), version=ANDROID_VERSION))
    logger.info('AVD name: {avd}'.format(avd=avd_name))
    is_first_run = not is_initialized(device)

    dp_size = os.getenv('DATAPARTITION', '16384')
    memory = os.getenv('RAM', '8192')

    if is_first_run:
        logger.info('Preparing emulator...')
        prepare_avd(device, avd_name, dp_size)

    logger.info('Run emulator...')

    if is_first_run:
        logger.info('Emulator was not previously initialized. Preparing a new one...')
        port = get_env_port_from_udid()
        cmd = 'emulator/emulator @{name} -port {port} -timezone Asia/Shanghai -no-boot-anim -gpu auto ' \
              '-accel on -wipe-data -writable-system -memory {memory} -partition-size {dp_size} ' \
              '-dns-server 10.32.51.10,10.32.51.12 -verbose {custom_args}'\
            .format(name=avd_name, port=port, memory=memory, dp_size=dp_size, custom_args=custom_args)
        logger.info('command: {cmd}'.format(cmd=cmd))
    else:
        logger.info('Using previously initialized AVD...')
        port = get_env_port_from_udid()
        cmd = 'emulator/emulator @{name} -port {port} -timezone Asia/Shanghai -no-boot-anim -gpu auto ' \
              '-accel on -verbose -writable-system -memory {memory} -partition-size {dp_size} ' \
              '-dns-server 10.32.51.10,10.32.51.12 {custom_args}' \
            .format(name=avd_name, port=port, memory=memory, dp_size=dp_size, custom_args=custom_args)
        logger.info('command: {cmd}'.format(cmd=cmd))

    appium = convert_str_to_bool(str(os.getenv('APPIUM', False)))
    if appium:
        subprocess.Popen(cmd.split())
        logger.info('Run appium server...')
        appium_run(avd_name)
    else:
        result = subprocess.Popen(cmd.split(), stdout=subprocess.PIPE).communicate()


if __name__ == '__main__':
    run()
