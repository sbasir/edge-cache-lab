/* generated using openapi-typescript-codegen -- do not edit */
/* istanbul ignore file */
/* tslint:disable */
/* eslint-disable */
import type { Product } from '../models/Product';
import type { ProductUpdate } from '../models/ProductUpdate';
import type { CancelablePromise } from '../core/CancelablePromise';
import { OpenAPI } from '../core/OpenAPI';
import { request as __request } from '../core/request';
export class AdminService {
    /**
     * Update product (triggers cache purge)
     * @param id Product ID
     * @param xPurgeToken Token required to authorize cache purge
     * @param requestBody
     * @returns Product Product updated successfully; purge initiated
     * @throws ApiError
     */
    public static updateProduct(
        id: string,
        xPurgeToken: string,
        requestBody: ProductUpdate,
    ): CancelablePromise<Product> {
        return __request(OpenAPI, {
            method: 'POST',
            url: '/admin/product/{id}',
            path: {
                'id': id,
            },
            headers: {
                'X-Purge-Token': xPurgeToken,
            },
            body: requestBody,
            mediaType: 'application/json',
            errors: {
                401: `Unauthorized; invalid or missing purge token`,
                404: `Product not found`,
            },
        });
    }
}
