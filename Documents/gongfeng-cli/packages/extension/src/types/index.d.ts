/* eslint-disable @typescript-eslint/naming-convention */
import { HashedList, PluralOptions, Replacements, TranslateOptions } from 'i18n';

declare global {
  /**
   * Translate the given phrase using locale configuration
   * @param phraseOrOptions - The phrase to translate or options for translation
   * @param replace
   * @returns The translated phrase
   */
  function __(phraseOrOptions: string | TranslateOptions, ...replace: string[]): string;
  /**
   * Translate the given phrase using locale configuration
   * @param phraseOrOptions - The phrase to translate or options for translation
   * @param replacements - An object containing replacements
   * @returns The translated phrase
   */
  function __(phraseOrOptions: string | TranslateOptions, replacements: Replacements): string;

  /**
   * Translate with plural condition the given phrase and count using locale configuration
   * @param phrase - Short phrase to be translated. All plural options ("one", "few", other", ...) have to be provided by your translation file
   * @param count - The number which allow to select from plural to singular
   * @returns The translated phrase
   */
  function __n(phrase: string, count: number): string;

  /**
   * Translate with plural condition the given phrase and count using locale configuration
   * @param options - Options for plural translate
   * @param [count] - The number which allow to select from plural to singular
   * @returns The translated phrase
   */
  function __n(options: PluralOptions, count?: number): string;
  /**
   * Translate with plural condition the given phrase and count using locale configuration
   * @param singular - The singular phrase to translate if count is <= 1
   * @param plural - The plural phrase to translate if count is > 1
   * @param count - The number which allow to select from plural to singular
   * @returns The translated phrase
   */
  function __n(singular: string, plural: string, count: number | string): string;

  /**
   * Translate the given phrase using locale configuration and MessageFormat
   * @param phraseOrOptions - The phrase to translate or options for translation
   * @param replace
   * @returns The translated phrase
   */
  function __mf(phraseOrOptions: string | TranslateOptions, ...replace: any[]): string;
  /**
   * Translate the given phrase using locale configuration and MessageFormat
   * @param phraseOrOptions - The phrase to translate or options for translation
   * @param replacements - An object containing replacements
   * @returns The translated phrase
   */
  function __mf(phraseOrOptions: string | TranslateOptions, replacements: Replacements): string;

  /**
   * Returns a list of translations for a given phrase in each language.
   * @param phrase - The phrase to get translations in each language
   * @returns The phrase in each language
   */
  function __l(phrase: string): string[];

  /**
   * Returns a hashed list of translations for a given phrase in each language.
   * @param phrase - The phrase to get translations in each language
   * @returns The phrase in each language
   */
  function __h(phrase: string): HashedList[];
}

export {};
