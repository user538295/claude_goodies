# Mermaid Diagram Examples

This reference provides examples of common Mermaid diagrams used in documentation.

## Table of Contents
1. [Flowcharts](#flowcharts)
2. [Sequence Diagrams](#sequence-diagrams)
3. [Class Diagrams](#class-diagrams)
4. [Entity Relationship Diagrams](#entity-relationship-diagrams)
5. [State Diagrams](#state-diagrams)
6. [C4 Architecture Diagrams](#c4-architecture-diagrams)

## Flowcharts

### Simple Process Flow
```mermaid
flowchart TD
    A[Start] --> B{Decision}
    B -->|Yes| C[Action 1]
    B -->|No| D[Action 2]
    C --> E[End]
    D --> E
```

### System Component Flow
```mermaid
flowchart LR
    Client[Client Application] --> Gateway[API Gateway]
    Gateway --> Auth[Auth Service]
    Gateway --> API[API Service]
    API --> DB[(Database)]
    API --> Cache[(Redis Cache)]
```

### Error Handling Flow
```mermaid
flowchart TD
    A[Request Received] --> B{Validate Input}
    B -->|Valid| C[Process Request]
    B -->|Invalid| D[Return 400 Error]
    C --> E{Processing Success?}
    E -->|Yes| F[Return 200 Response]
    E -->|No| G[Log Error]
    G --> H{Retry Possible?}
    H -->|Yes| C
    H -->|No| I[Return 500 Error]
```

## Sequence Diagrams

### API Request Flow
```mermaid
sequenceDiagram
    participant C as Client
    participant G as Gateway
    participant A as Auth Service
    participant S as API Service
    participant D as Database

    C->>G: POST /api/resource
    G->>A: Validate token
    A-->>G: Token valid
    G->>S: Forward request
    S->>D: Query data
    D-->>S: Return data
    S-->>G: Response
    G-->>C: 200 OK
```

### Authentication Flow
```mermaid
sequenceDiagram
    participant U as User
    participant A as App
    participant I as Identity Provider
    participant S as Service

    U->>A: Login
    A->>I: Authenticate (credentials)
    I-->>A: JWT Token
    A->>S: Request (with token)
    S->>I: Validate token
    I-->>S: Token valid
    S-->>A: Protected resource
    A-->>U: Display data
```

## Class Diagrams

### Domain Model
```mermaid
classDiagram
    class User {
        +String id
        +String email
        +String name
        +login()
        +logout()
    }
    
    class Order {
        +String id
        +DateTime createdAt
        +Decimal total
        +calculateTotal()
        +submit()
    }
    
    class OrderItem {
        +String id
        +Integer quantity
        +Decimal price
    }
    
    class Product {
        +String id
        +String name
        +Decimal price
    }
    
    User "1" --> "*" Order : places
    Order "1" --> "*" OrderItem : contains
    OrderItem "*" --> "1" Product : references
```

### Service Architecture
```mermaid
classDiagram
    class IRepository {
        <<interface>>
        +find(id)
        +save(entity)
        +delete(id)
    }
    
    class UserRepository {
        +find(id)
        +save(entity)
        +delete(id)
        +findByEmail(email)
    }
    
    class UserService {
        -repository
        +getUser(id)
        +createUser(data)
        +updateUser(id, data)
    }
    
    IRepository <|.. UserRepository : implements
    UserService --> UserRepository : uses
```

## Entity Relationship Diagrams

### Database Schema
```mermaid
erDiagram
    USER ||--o{ ORDER : places
    USER {
        uuid id PK
        string email UK
        string name
        datetime created_at
    }
    
    ORDER ||--|{ ORDER_ITEM : contains
    ORDER {
        uuid id PK
        uuid user_id FK
        decimal total
        datetime created_at
    }
    
    ORDER_ITEM }o--|| PRODUCT : references
    ORDER_ITEM {
        uuid id PK
        uuid order_id FK
        uuid product_id FK
        integer quantity
        decimal price
    }
    
    PRODUCT {
        uuid id PK
        string name
        decimal price
        integer stock
    }
```

### Multi-Tenant Schema
```mermaid
erDiagram
    TENANT ||--o{ USER : has
    TENANT ||--o{ PROJECT : owns
    
    TENANT {
        uuid id PK
        string name
        string subdomain UK
    }
    
    USER {
        uuid id PK
        uuid tenant_id FK
        string email
        string role
    }
    
    PROJECT {
        uuid id PK
        uuid tenant_id FK
        string name
        datetime created_at
    }
    
    PROJECT ||--o{ TASK : contains
    TASK {
        uuid id PK
        uuid project_id FK
        uuid assigned_to FK
        string title
        string status
    }
    
    USER ||--o{ TASK : assigned
```

## State Diagrams

### Order Lifecycle
```mermaid
stateDiagram-v2
    [*] --> Draft
    Draft --> Pending : submit()
    Pending --> Processing : approve()
    Pending --> Cancelled : cancel()
    Processing --> Completed : fulfill()
    Processing --> Failed : error()
    Failed --> Processing : retry()
    Completed --> [*]
    Cancelled --> [*]
```

### Connection State Machine
```mermaid
stateDiagram-v2
    [*] --> Disconnected
    Disconnected --> Connecting : connect()
    Connecting --> Connected : success
    Connecting --> Failed : timeout
    Connected --> Disconnected : disconnect()
    Connected --> Reconnecting : connection lost
    Reconnecting --> Connected : success
    Reconnecting --> Failed : max retries
    Failed --> Disconnected : reset()
```

## C4 Architecture Diagrams

### System Context (Level 1)
```mermaid
graph TB
    User[User]
    Admin[Administrator]
    
    System[E-Commerce Platform]
    
    Email[Email Service<br/>External]
    Payment[Payment Gateway<br/>External]
    Analytics[Analytics Service<br/>External]
    
    User --> System
    Admin --> System
    System --> Email
    System --> Payment
    System --> Analytics
    
    style System fill:#1168bd,stroke:#0b4884,color:#fff
    style Email fill:#999,stroke:#666,color:#fff
    style Payment fill:#999,stroke:#666,color:#fff
    style Analytics fill:#999,stroke:#666,color:#fff
```

### Container Diagram (Level 2)
```mermaid
graph TB
    User[User]
    
    subgraph Platform["E-Commerce Platform"]
        WebApp[Web Application<br/>React]
        API[API Gateway<br/>Node.js]
        Auth[Auth Service<br/>Node.js]
        Orders[Order Service<br/>Python]
        Products[Product Service<br/>Python]
        
        DB[(Database<br/>PostgreSQL)]
        Cache[(Cache<br/>Redis)]
        Queue[Message Queue<br/>RabbitMQ]
    end
    
    Email[Email Service]
    Payment[Payment Gateway]
    
    User --> WebApp
    WebApp --> API
    API --> Auth
    API --> Orders
    API --> Products
    
    Orders --> DB
    Products --> DB
    Orders --> Cache
    Products --> Cache
    Orders --> Queue
    Queue --> Email
    Orders --> Payment
    
    style WebApp fill:#438dd5,stroke:#2e6295,color:#fff
    style API fill:#438dd5,stroke:#2e6295,color:#fff
    style Auth fill:#438dd5,stroke:#2e6295,color:#fff
    style Orders fill:#438dd5,stroke:#2e6295,color:#fff
    style Products fill:#438dd5,stroke:#2e6295,color:#fff
```

### Component Diagram (Level 3)
```mermaid
graph TB
    API[API Gateway]
    
    subgraph OrderService["Order Service"]
        OrderController[Order Controller]
        OrderManager[Order Manager]
        OrderRepository[Order Repository]
        PaymentClient[Payment Client]
        NotificationClient[Notification Client]
    end
    
    DB[(Database)]
    Payment[Payment Gateway]
    Queue[Message Queue]
    
    API --> OrderController
    OrderController --> OrderManager
    OrderManager --> OrderRepository
    OrderManager --> PaymentClient
    OrderManager --> NotificationClient
    
    OrderRepository --> DB
    PaymentClient --> Payment
    NotificationClient --> Queue
    
    style OrderController fill:#85bbf0,stroke:#5d9cd6,color:#000
    style OrderManager fill:#85bbf0,stroke:#5d9cd6,color:#000
    style OrderRepository fill:#85bbf0,stroke:#5d9cd6,color:#000
    style PaymentClient fill:#85bbf0,stroke:#5d9cd6,color:#000
    style NotificationClient fill:#85bbf0,stroke:#5d9cd6,color:#000
```

## Deployment Diagrams

### Infrastructure Overview
```mermaid
graph TB
    subgraph Internet
        Users[Users]
        Admins[Administrators]
    end
    
    subgraph AWS["AWS Cloud"]
        subgraph VPC["Virtual Private Cloud"]
            subgraph Public["Public Subnet"]
                ALB[Application Load Balancer]
                NAT[NAT Gateway]
            end
            
            subgraph Private["Private Subnet"]
                ECS[ECS Cluster<br/>Container Services]
                RDS[(RDS<br/>PostgreSQL)]
                ElastiCache[(ElastiCache<br/>Redis)]
            end
        end
        
        S3[S3<br/>Static Assets]
        CloudFront[CloudFront CDN]
    end
    
    Users --> CloudFront
    Admins --> ALB
    CloudFront --> S3
    CloudFront --> ALB
    ALB --> ECS
    ECS --> RDS
    ECS --> ElastiCache
    ECS --> NAT
    
    style VPC fill:#f0f0f0,stroke:#666
    style Public fill:#e6f3ff,stroke:#666
    style Private fill:#fff0e6,stroke:#666
```

## Tips for Effective Diagrams

1. **Keep it simple**: Focus on essential elements only
2. **Use consistent styling**: Apply same colors/shapes for similar concepts
3. **Label clearly**: Every node should have a descriptive label
4. **Show relationships**: Use appropriate arrows and connectors
5. **Add legends**: When using colors or symbols, explain them
6. **Limit complexity**: Break complex diagrams into multiple simpler ones
7. **Update regularly**: Keep diagrams in sync with code changes

## When to Use Each Diagram Type

- **Flowcharts**: Process flows, decision trees, algorithms
- **Sequence**: API interactions, authentication flows, temporal processes
- **Class**: Domain models, service architecture, inheritance
- **ERD**: Database schemas, data relationships
- **State**: Lifecycle management, connection handling, workflows
- **C4**: System architecture at different zoom levels
