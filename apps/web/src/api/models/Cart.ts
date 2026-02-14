/* generated using openapi-typescript-codegen -- do not edit */
/* istanbul ignore file */
/* tslint:disable */
/* eslint-disable */
import type { CartItem } from './CartItem';
import type { ResponseMeta } from './ResponseMeta';
export type Cart = {
    id: string;
    items: Array<CartItem>;
    total: number;
    currency?: string;
    meta: ResponseMeta;
};

