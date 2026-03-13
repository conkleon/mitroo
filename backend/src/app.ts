import express from "express";
import cors from "cors";
import helmet from "helmet";
import morgan from "morgan";
import cookieParser from "cookie-parser";
import path from "path";

import { errorHandler } from "./middleware/errorHandler";
import { notFound } from "./middleware/notFound";

import healthRoutes from "./routes/health.routes";
import authRoutes from "./routes/auth.routes";
import userRoutes from "./routes/user.routes";
import departmentRoutes from "./routes/department.routes";
import serviceRoutes from "./routes/service.routes";
import itemRoutes from "./routes/item.routes";
import vehicleRoutes from "./routes/vehicle.routes";
import specializationRoutes from "./routes/specialization.routes";
import trainingApplicationRoutes from "./routes/trainingApplication.routes";
import fileRoutes from "./routes/file.routes";
import categoryRoutes from "./routes/category.routes";

const app = express();

// ── Global middleware ───────────────────────────
app.use(helmet());
app.use(cors({ origin: true, credentials: true }));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(cookieParser());
app.use(morgan("dev"));

// Serve uploaded files statically
app.use("/uploads", express.static(path.resolve(__dirname, "../uploads")));

// ── Routes ──────────────────────────────────────
app.use("/api/health", healthRoutes);
app.use("/api/auth", authRoutes);
app.use("/api/users", userRoutes);
app.use("/api/departments", departmentRoutes);
app.use("/api/services", serviceRoutes);
app.use("/api/items", itemRoutes);
app.use("/api/vehicles", vehicleRoutes);
app.use("/api/specializations", specializationRoutes);
app.use("/api/training-applications", trainingApplicationRoutes);
app.use("/api/files", fileRoutes);
app.use("/api/item-categories", categoryRoutes);

// ── Error handling ──────────────────────────────
app.use(notFound);
app.use(errorHandler);

export default app;
