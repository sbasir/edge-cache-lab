/* generated using openapi-typescript-codegen -- do not edit */
/* istanbul ignore file */
/* tslint:disable */
/* eslint-disable */
import type { Account } from '../models/Account';
import type { Cart } from '../models/Cart';
import type { CancelablePromise } from '../core/CancelablePromise';
import { OpenAPI } from '../core/OpenAPI';
import { request as __request } from '../core/request';
export class PrivateService {
    /**
     * Get user cart (non-cacheable)
     * @returns Cart User cart contents
     * @throws ApiError
     */
    public static getCart(): CancelablePromise<Cart> {
        return __request(OpenAPI, {
            method: 'GET',
            url: '/cart',
        });
    }
    /**
     * Get user account info (non-cacheable)
     * @returns Account User account information
     * @throws ApiError
     */
    public static getAccount(): CancelablePromise<Account> {
        return __request(OpenAPI, {
            method: 'GET',
            url: '/account',
        });
    }
}
