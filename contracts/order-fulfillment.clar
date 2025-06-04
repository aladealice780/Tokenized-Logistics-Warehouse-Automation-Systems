;; Order Fulfillment Contract
;; Manages automated order fulfillment process

(define-constant ERR_UNAUTHORIZED (err u300))
(define-constant ERR_ORDER_NOT_FOUND (err u301))
(define-constant ERR_INSUFFICIENT_INVENTORY (err u302))
(define-constant ERR_ORDER_ALREADY_PROCESSED (err u303))
(define-constant ERR_INVALID_STATUS (err u304))

;; Order status constants
(define-constant STATUS_PENDING "PENDING")
(define-constant STATUS_PROCESSING "PROCESSING")
(define-constant STATUS_FULFILLED "FULFILLED")
(define-constant STATUS_CANCELLED "CANCELLED")

;; Order structure
(define-map orders
  { order-id: uint }
  {
    customer: principal,
    warehouse-id: uint,
    items: (list 10 { item-id: uint, quantity: uint }),
    status: (string-ascii 20),
    created-at: uint,
    processed-at: uint,
    fulfilled-at: uint,
    total-value: uint,
    priority: uint
  }
)

;; Order fulfillment queue
(define-map fulfillment-queue
  { queue-position: uint }
  {
    order-id: uint,
    warehouse-id: uint,
    priority: uint,
    estimated-time: uint
  }
)

(define-data-var next-order-id uint u1)
(define-data-var queue-length uint u0)

;; Create new order
(define-public (create-order
  (warehouse-id uint)
  (items (list 10 { item-id: uint, quantity: uint }))
  (total-value uint)
  (priority uint))
  (let ((order-id (var-get next-order-id)))
    (map-set orders
      { order-id: order-id }
      {
        customer: tx-sender,
        warehouse-id: warehouse-id,
        items: items,
        status: STATUS_PENDING,
        created-at: block-height,
        processed-at: u0,
        fulfilled-at: u0,
        total-value: total-value,
        priority: priority
      }
    )

    ;; Add to fulfillment queue
    (let ((queue-pos (var-get queue-length)))
      (map-set fulfillment-queue
        { queue-position: queue-pos }
        {
          order-id: order-id,
          warehouse-id: warehouse-id,
          priority: priority,
          estimated-time: (+ block-height u10) ;; Estimated 10 blocks
        }
      )
      (var-set queue-length (+ queue-pos u1))
    )

    (var-set next-order-id (+ order-id u1))
    (ok order-id)
  )
)

;; Process order (automated)
(define-public (process-order (order-id uint))
  (let ((order (unwrap! (map-get? orders { order-id: order-id }) ERR_ORDER_NOT_FOUND)))
    (asserts! (is-eq (get status order) STATUS_PENDING) ERR_ORDER_ALREADY_PROCESSED)

    ;; Update order status to processing
    (map-set orders
      { order-id: order-id }
      (merge order {
        status: STATUS_PROCESSING,
        processed-at: block-height
      })
    )
    (ok true)
  )
)

;; Fulfill order
(define-public (fulfill-order (order-id uint))
  (let ((order (unwrap! (map-get? orders { order-id: order-id }) ERR_ORDER_NOT_FOUND)))
    (asserts! (is-eq (get status order) STATUS_PROCESSING) ERR_INVALID_STATUS)

    ;; Update order status to fulfilled
    (map-set orders
      { order-id: order-id }
      (merge order {
        status: STATUS_FULFILLED,
        fulfilled-at: block-height
      })
    )
    (ok true)
  )
)

;; Get order details
(define-read-only (get-order (order-id uint))
  (map-get? orders { order-id: order-id })
)

;; Get order status
(define-read-only (get-order-status (order-id uint))
  (match (map-get? orders { order-id: order-id })
    order (some (get status order))
    none
  )
)

;; Get queue position
(define-read-only (get-queue-info (queue-position uint))
  (map-get? fulfillment-queue { queue-position: queue-position })
)
