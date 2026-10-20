# ClusterIP vs LoadBalancer — Port Exposure Explained

Both `ClusterIP` and `LoadBalancer` expose ports, but they do so at **different network levels**.

---

## 1. ClusterIP — Internal Access

- Exposes a Service on a **cluster-internal IP and port**
- Accessible by other Pods and Services **inside the cluster**
- **Not directly accessible** from outside the cluster under normal networking
- Example: `http://users-api:8080`

---

## 2. LoadBalancer — External Access

- Exposes a Service through an **external load balancer** when the environment supports one
- Provides an **external IP or hostname** and a port
- Routes incoming traffic to healthy backend Pods through the Service
- Example: `http://<EXTERNAL-IP>:8080`

---

## Architecture Diagram

```
External user / browser
        │
        ▼
LoadBalancer Service
  External IP : 8080
        │
        ├──► Pod 1
        ├──► Pod 2
        └──► Pod 3

Internal communication uses a ClusterIP Service instead:

Pod A ──► ClusterIP Service (cluster-internal IP : 8080) ──► Pod B
```

---

## Does ClusterIP Expose a Port?

**Yes!** The key difference is *where* that port is accessible.

| Feature | ClusterIP | LoadBalancer |
|---------|-----------|--------------|
| Port exists? | ✅ Yes | ✅ Yes |
| Internal cluster access | ✅ Yes | ✅ Yes |
| External IP / hostname | ❌ Normally no | ✅ Yes, when supported |
| Typical use | Internal APIs, databases | Public-facing applications |
| External user access | ❌ Not directly | ✅ Yes |

---

## Example — ClusterIP Service YAML

```yaml
apiVersion: v1
kind: Service
metadata:
  name: users-api
spec:
  type: ClusterIP
  selector:
    app: users-api
  ports:
    - port: 8080
      targetPort: 3000
```

- `port: 8080` — the port exposed by the Service **inside the cluster**
- `targetPort: 3000` — the port the application listens on **inside the Pod**
- External users **cannot** connect directly to `users-api:8080`

---

## Applying This to the Microservices Demo Project

For the Kubernetes demo with `users-api`, `tasks-api`, and `auth-api`:

| Service | Type | Reason |
|---------|------|--------|
| `users-api` | `LoadBalancer` | Needs external access for `/login` |
| `tasks-api` | `LoadBalancer` | Needs external access for `/tasks` |
| `auth-api` | `ClusterIP` | Internal only — accessed only by `users-api` and `tasks-api` |

---

## Security Note

> A `ClusterIP` Service is **not itself a security boundary**.
> Use **Kubernetes NetworkPolicies** and appropriate **authentication** to properly restrict access between services.

---

## Summary

| | ClusterIP | LoadBalancer |
|--|-----------|--------------|
| Exposes a port? | ✅ Yes — internally | ✅ Yes — externally |
| Who can reach it? | Pods inside the cluster | Anyone on the internet (when supported) |
| Use for | Internal APIs, auth, databases | Public-facing endpoints |

> **Remember:** `ClusterIP` exposes a port internally. `LoadBalancer` provides an externally reachable entry point when supported by the environment (cloud provider or Minikube tunnel).
