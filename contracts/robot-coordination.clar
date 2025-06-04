;; Robot Coordination Contract
;; Coordinates warehouse robots and their tasks

(define-constant ERR_UNAUTHORIZED (err u400))
(define-constant ERR_ROBOT_NOT_FOUND (err u401))
(define-constant ERR_ROBOT_BUSY (err u402))
(define-constant ERR_INVALID_TASK (err u403))
(define-constant ERR_TASK_NOT_FOUND (err u404))

;; Robot status constants
(define-constant STATUS_IDLE "IDLE")
(define-constant STATUS_BUSY "BUSY")
(define-constant STATUS_MAINTENANCE "MAINTENANCE")
(define-constant STATUS_OFFLINE "OFFLINE")

;; Robot structure
(define-map robots
  { robot-id: uint }
  {
    warehouse-id: uint,
    robot-type: (string-ascii 20), ;; "PICKER", "MOVER", "SORTER"
    status: (string-ascii 20),
    current-zone: (string-ascii 20),
    battery-level: uint,
    last-maintenance: uint,
    tasks-completed: uint,
    efficiency-score: uint
  }
)

;; Task structure
(define-map robot-tasks
  { task-id: uint }
  {
    robot-id: uint,
    task-type: (string-ascii 30), ;; "PICK", "MOVE", "SORT", "RESTOCK"
    priority: uint,
    source-zone: (string-ascii 20),
    target-zone: (string-ascii 20),
    item-id: uint,
    quantity: uint,
    status: (string-ascii 20),
    assigned-at: uint,
    completed-at: uint,
    estimated-duration: uint
  }
)

(define-data-var next-robot-id uint u1)
(define-data-var next-task-id uint u1)

;; Register new robot
(define-public (register-robot
  (warehouse-id uint)
  (robot-type (string-ascii 20))
  (initial-zone (string-ascii 20)))
  (let ((robot-id (var-get next-robot-id)))
    (map-set robots
      { robot-id: robot-id }
      {
        warehouse-id: warehouse-id,
        robot-type: robot-type,
        status: STATUS_IDLE,
        current-zone: initial-zone,
        battery-level: u100,
        last-maintenance: block-height,
        tasks-completed: u0,
        efficiency-score: u100
      }
    )
    (var-set next-robot-id (+ robot-id u1))
    (ok robot-id)
  )
)

;; Assign task to robot
(define-public (assign-task
  (robot-id uint)
  (task-type (string-ascii 30))
  (priority uint)
  (source-zone (string-ascii 20))
  (target-zone (string-ascii 20))
  (item-id uint)
  (quantity uint)
  (estimated-duration uint))
  (let ((robot (unwrap! (map-get? robots { robot-id: robot-id }) ERR_ROBOT_NOT_FOUND))
        (task-id (var-get next-task-id)))
    (asserts! (is-eq (get status robot) STATUS_IDLE) ERR_ROBOT_BUSY)

    ;; Create task
    (map-set robot-tasks
      { task-id: task-id }
      {
        robot-id: robot-id,
        task-type: task-type,
        priority: priority,
        source-zone: source-zone,
        target-zone: target-zone,
        item-id: item-id,
        quantity: quantity,
        status: "ASSIGNED",
        assigned-at: block-height,
        completed-at: u0,
        estimated-duration: estimated-duration
      }
    )

    ;; Update robot status
    (map-set robots
      { robot-id: robot-id }
      (merge robot { status: STATUS_BUSY })
    )

    (var-set next-task-id (+ task-id u1))
    (ok task-id)
  )
)

;; Complete task
(define-public (complete-task (task-id uint))
  (let ((task (unwrap! (map-get? robot-tasks { task-id: task-id }) ERR_TASK_NOT_FOUND))
        (robot-id (get robot-id task))
        (robot (unwrap! (map-get? robots { robot-id: robot-id }) ERR_ROBOT_NOT_FOUND)))

    ;; Update task status
    (map-set robot-tasks
      { task-id: task-id }
      (merge task {
        status: "COMPLETED",
        completed-at: block-height
      })
    )

    ;; Update robot status and stats
    (map-set robots
      { robot-id: robot-id }
      (merge robot {
        status: STATUS_IDLE,
        current-zone: (get target-zone task),
        tasks-completed: (+ (get tasks-completed robot) u1)
      })
    )
    (ok true)
  )
)

;; Update robot battery level
(define-public (update-battery-level (robot-id uint) (battery-level uint))
  (let ((robot (unwrap! (map-get? robots { robot-id: robot-id }) ERR_ROBOT_NOT_FOUND)))
    (map-set robots
      { robot-id: robot-id }
      (merge robot { battery-level: battery-level })
    )
    (ok true)
  )
)

;; Get robot details
(define-read-only (get-robot (robot-id uint))
  (map-get? robots { robot-id: robot-id })
)

;; Get task details
(define-read-only (get-task (task-id uint))
  (map-get? robot-tasks { task-id: task-id })
)

;; Check if robot is available
(define-read-only (is-robot-available (robot-id uint))
  (match (map-get? robots { robot-id: robot-id })
    robot (and (is-eq (get status robot) STATUS_IDLE) (> (get battery-level robot) u20))
    false
  )
)
