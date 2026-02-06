import * as os from 'os';
import * as path from 'path';
import * as winston from 'winston';
import * as DailyRotateFile from 'winston-daily-rotate-file';
import * as Transport from 'winston-transport';

const isWindows = os.platform() === 'win32';
const home = process.env.HOME || (isWindows && windowsHome()) || os.homedir() || os.tmpdir();
const dirname = 'gf';
const logFilename = '/gf-cli-%DATE%.log';
const exceptionLogFilename = '/gf-cli-exception-%DATE%.log';
const rejectLogFilename = '/gf-cli-reject-%DATE%.log';

const logFormat = winston.format.combine(
  winston.format.errors({ stack: true }),
  winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss:SSS' }),
  winston.format.align(),
  winston.format.printf((info) => `${info.timestamp} ${info.level}: ${info.message}`),
);

const transports: Transport[] = [
  new DailyRotateFile({
    filename: `${cacheDir()}/${logFilename}`,
    datePattern: 'YYYY-MM-DD',
    maxSize: '20m',
    maxFiles: '30d',
    level: 'info',
  }),
];

const exceptionHandlers: Transport[] = [
  new DailyRotateFile({
    filename: `${cacheDir()}/${exceptionLogFilename}`,
    datePattern: 'YYYY-MM-DD',
    maxSize: '20m',
    maxFiles: '30d',
    level: 'info',
  }),
];

const rejectionHandlers: Transport[] = [
  new DailyRotateFile({
    filename: `${cacheDir()}/${rejectLogFilename}`,
    datePattern: 'YYYY-MM-DD',
    maxSize: '20m',
    maxFiles: '30d',
    level: 'info',
  }),
];

if (process.env.NODE_ENV === 'development') {
  const consoleTransport = new winston.transports.Console({
    level: 'debug',
  });
  transports.push(consoleTransport);
}

function windowsHomedriveHome() {
  return process.env.HOMEDRIVE && process.env.HOMEPATH && path.join(process.env.HOMEDRIVE!, process.env.HOMEPATH!);
}

function windowsUserprofileHome() {
  return process.env.USERPROFILE;
}

function windowsHome() {
  return windowsHomedriveHome() || windowsUserprofileHome();
}

function macosCacheDir() {
  return (os.platform() === 'darwin' && path.join(home, 'Library', 'Caches', dirname)) || undefined;
}

function dir(category: 'cache' | 'data' | 'config'): string {
  const base =
    process.env[`XDG_${category.toUpperCase()}_HOME`] ||
    (isWindows && process.env.LOCALAPPDATA) ||
    path.join(home, category === 'data' ? '.local/share' : `.${category}`);
  return path.join(base, dirname);
}

function cacheDir() {
  return macosCacheDir() || dir('cache');
}

const logger = winston.createLogger({
  format: logFormat,
  transports,
  exceptionHandlers,
  rejectionHandlers,
});

export default logger;
