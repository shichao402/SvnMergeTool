import * as chalk from 'chalk';

/**
 * 统一 CLI 在命令行不同级别的颜色
 */
class Color {
  public bold(msg: string) {
    return chalk.bold(msg);
  }

  public dim(msg: string) {
    return chalk.dim(msg);
  }

  public gray(msg: string) {
    return chalk.hex('#96969A')(msg);
  }

  public brand(msg: string) {
    return chalk.hex('#415B94')(msg);
  }

  public info(msg: string) {
    return chalk.hex('#4B8CBF')(msg);
  }

  public warn(msg: string) {
    return chalk.hex('#EDAD33')(msg);
  }

  public success(msg: string) {
    return chalk.hex('#42916F')(msg);
  }

  public error(msg: string) {
    return chalk.hex('#B63154')(msg);
  }

  public inverse(msg: string) {
    return chalk.inverse(msg);
  }
}

const color = new Color();

export default color;
