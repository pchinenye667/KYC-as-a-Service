;; KYC-as-a-Service Smart Contract
;; Privacy-preserving identity verification linked to wallets

;; Contract constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-unauthorized (err u101))
(define-constant err-already-verified (err u102))
(define-constant err-not-verified (err u103))
(define-constant err-invalid-provider (err u104))

;; Data variables
(define-data-var next-verification-id uint u1)

;; Data maps
(define-map wallet-kyc-status 
    principal 
    {
        verified: bool,
        verification-level: uint,
        provider-hash: (buff 32),
        timestamp: uint,
        verification-id: uint
    }
)

(define-map kyc-providers
    (buff 32)
    {
        name: (string-ascii 50),
        active: bool,
        reputation-score: uint
    }
)

(define-map verification-records
    uint
    {
        wallet: principal,
        provider-hash: (buff 32),
        document-hash: (buff 32),
        verification-level: uint,
        timestamp: uint
    }
)

;; Read-only functions
(define-read-only (get-kyc-status (wallet principal))
    (map-get? wallet-kyc-status wallet)
)

(define-read-only (is-wallet-verified (wallet principal))
    (match (map-get? wallet-kyc-status wallet)
        kyc-data (get verified kyc-data)
        false
    )
)

(define-read-only (get-verification-level (wallet principal))
    (match (map-get? wallet-kyc-status wallet)
        kyc-data (if (get verified kyc-data)
                    (some (get verification-level kyc-data))
                    none)
        none
    )
)

(define-read-only (get-provider-info (provider-hash (buff 32)))
    (map-get? kyc-providers provider-hash)
)

(define-read-only (get-verification-record (verification-id uint))
    (map-get? verification-records verification-id)
)

;; Private functions
(define-private (is-authorized-provider (provider-hash (buff 32)))
    (match (map-get? kyc-providers provider-hash)
        provider-info (get active provider-info)
        false
    )
)

;; Public functions
(define-public (register-kyc-provider 
    (provider-hash (buff 32))
    (name (string-ascii 50))
    (initial-reputation uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (map-set kyc-providers provider-hash {
            name: name,
            active: true,
            reputation-score: initial-reputation
        }))
    )
)

(define-public (deactivate-provider (provider-hash (buff 32)))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (match (map-get? kyc-providers provider-hash)
            provider-info 
            (begin
                (map-set kyc-providers provider-hash 
                    (merge provider-info { active: false }))
                (ok true))
            (err u104)
        )
    )
)

(define-public (verify-wallet
    (wallet principal)
    (provider-hash (buff 32))
    (document-hash (buff 32))
    (verification-level uint))
    (let 
        (
            (current-verification-id (var-get next-verification-id))
        )
        (begin
            (asserts! (is-authorized-provider provider-hash) err-invalid-provider)
            (asserts! (is-none (map-get? wallet-kyc-status wallet)) err-already-verified)

            ;; Store verification record
            (map-set verification-records current-verification-id {
                wallet: wallet,
                provider-hash: provider-hash,
                document-hash: document-hash,
                verification-level: verification-level,
                timestamp: block-height
            })

            ;; Update wallet KYC status
            (map-set wallet-kyc-status wallet {
                verified: true,
                verification-level: verification-level,
                provider-hash: provider-hash,
                timestamp: block-height,
                verification-id: current-verification-id
            })

            ;; Increment verification ID counter
            (var-set next-verification-id (+ current-verification-id u1))

            (ok current-verification-id)
        )
    )
)

(define-public (update-verification-level
    (wallet principal)
    (new-level uint)
    (provider-hash (buff 32)))
    (begin
        (asserts! (is-authorized-provider provider-hash) (err u104))
        (match (map-get? wallet-kyc-status wallet)
            current-status
            (begin
                (asserts! (get verified current-status) (err u103))
                (map-set wallet-kyc-status wallet 
                    (merge current-status { 
                        verification-level: new-level,
                        timestamp: block-height
                    }))
                (ok true)
            )
            (err u103)
        )
    )
)

(define-public (revoke-verification (wallet principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) (err u100))
        (match (map-get? wallet-kyc-status wallet)
            current-status
            (begin
                (map-set wallet-kyc-status wallet 
                    (merge current-status { verified: false }))
                (ok true))
            (err u103)
        )
    )
)

(define-public (update-provider-reputation
    (provider-hash (buff 32))
    (new-reputation uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) (err u100))
        (match (map-get? kyc-providers provider-hash)
            provider-info
            (begin
                (map-set kyc-providers provider-hash 
                    (merge provider-info { reputation-score: new-reputation }))
                (ok true))
            (err u104)
        )
    )
)