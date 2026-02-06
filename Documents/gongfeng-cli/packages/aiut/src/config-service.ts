import ApiService from './api-service';
import { GenScene } from './type';
import { getPlatform } from './utils';
import { logger } from '@tencent/gongfeng-cli-base';

export interface Option {
  label: string;
  value: string;
}

export interface ModelOption extends Option {
  tips: string;
  info: string;
}

export type ModelsConfig = Partial<Record<GenScene, ModelOption[]>>;

export interface ErrorTipItem {
  errorCode: number;
  errorMessage: string;
  guideLink: string;
  guideText: string;
}

export interface FrameworkOption extends Option {
  style?: Option[];
}

export interface ConfigItem {
  type: string;
  defaultValue: string;
  key: string;
  label: string;
  options: Option[];
  required: boolean;
  tip?: string;
}

interface Config {
  url: string;
  version: string;
  models: Record<string, ModelsConfig>;
  frameworks: Record<string, FrameworkOption[]>;
  defaultLanguage: string;
  defaultFramework: string;
  errorTips: ErrorTipItem[];
  langConfig: {
    [key: string]: ConfigItem[];
  };
}

class ConfigService {
  private config: Config | null = null;
  constructor(private apiService: ApiService) {}
  async fetchConfig() {
    const {
      url,
      version,
      model_config_by_lang: modelConfig,
      frameworks: frameworksStr,
      default_lang: defaultLanguage,
      default_framework: defaultFrameworkStr,
      error_tips: errorTipsStr,
      lang_config: langConfigStr,
    } = await this.apiService.getConfig(getPlatform());
    let models = [];
    let defaultFramework = '';
    let frameworks = [];
    let errorTips = [];
    let langConfig = {};
    try {
      models = JSON.parse(modelConfig);
      frameworks = JSON.parse(frameworksStr);
      defaultFramework = JSON.parse(defaultFrameworkStr)[defaultLanguage];
      errorTips = JSON.parse(errorTipsStr);
      langConfig = JSON.parse(langConfigStr);
    } catch (error) {
      logger.error('get models failed', error);
    }
    this.config = {
      models,
      url,
      version,
      frameworks,
      defaultLanguage,
      defaultFramework,
      errorTips,
      langConfig,
    };
    return this.config;
  }
  async getConfig(): Promise<Config> {
    if (!this.config) {
      await this.fetchConfig();
    }
    return this.config!;
  }
  get<K extends keyof Config>(key: K): Config[K] | undefined {
    return this.config?.[key];
  }
  getModels(language: string, scene: GenScene) {
    return this.config?.models[language][scene] || [];
  }
  getFrameworks(language: string) {
    return this.config?.frameworks[language] || [];
  }
}

export default ConfigService;
