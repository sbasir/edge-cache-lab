/* generated using openapi-typescript-codegen -- do not edit */
/* istanbul ignore file */
/* tslint:disable */
/* eslint-disable */
import type { Category } from '../models/Category';
import type { Homepage } from '../models/Homepage';
import type { Product } from '../models/Product';
import type { ResponseMeta } from '../models/ResponseMeta';
import type { CancelablePromise } from '../core/CancelablePromise';
import { OpenAPI } from '../core/OpenAPI';
import { request as __request } from '../core/request';
export class PublicService {
    /**
     * Get homepage content
     * @returns Homepage Homepage content
     * @throws ApiError
     */
    public static getHomepage(): CancelablePromise<Homepage> {
        return __request(OpenAPI, {
            method: 'GET',
            url: '/',
        });
    }
    /**
     * List all product categories
     * @returns any List of categories
     * @throws ApiError
     */
    public static listCategories(): CancelablePromise<{
        categories?: Array<Category>;
        meta?: ResponseMeta;
    }> {
        return __request(OpenAPI, {
            method: 'GET',
            url: '/category',
        });
    }
    /**
     * Get product details
     * @param id Product ID
     * @returns Product Product details
     * @throws ApiError
     */
    public static getProduct(
        id: string,
    ): CancelablePromise<Product> {
        return __request(OpenAPI, {
            method: 'GET',
            url: '/product/{id}',
            path: {
                'id': id,
            },
            errors: {
                404: `Product not found`,
            },
        });
    }
}
