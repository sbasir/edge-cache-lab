/* generated using openapi-typescript-codegen -- do not edit */
/* istanbul ignore file */
/* tslint:disable */
/* eslint-disable */
import type { Health } from '../models/Health';
import type { CancelablePromise } from '../core/CancelablePromise';
import { OpenAPI } from '../core/OpenAPI';
import { request as __request } from '../core/request';
export class SystemService {
    /**
     * Health check endpoint
     * @returns Health Service is healthy
     * @throws ApiError
     */
    public static getHealth(): CancelablePromise<Health> {
        return __request(OpenAPI, {
            method: 'GET',
            url: '/health',
        });
    }
}
